`timescale 1ns/1ps
//============================================================================
// Module:      axi_master_if
// Project:     AI_GLASSES — AXI Interconnect
// Description: Per-master interface: ID prefix insertion + address decode +
//              outstanding transaction tracking. Prepends 3-bit master ID
//              prefix to incoming AXI ID. Runs address through decoder to
//              determine target slave.
//============================================================================

module axi_master_if #(
    parameter MASTER_ID       = 0,
    parameter NUM_SLAVES      = 5,
    parameter DATA_WIDTH      = 32,
    parameter ADDR_WIDTH      = 32,
    parameter ID_WIDTH        = 6,
    parameter ID_PREFIX_WIDTH = 3,
    parameter OUTSTANDING     = 2
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // External master AXI interface (original ID width = ID_WIDTH - ID_PREFIX_WIDTH)
    input  wire [ID_WIDTH-ID_PREFIX_WIDTH-1:0] ext_awid,
    input  wire [ADDR_WIDTH-1:0]               ext_awaddr,
    input  wire [7:0]                          ext_awlen,
    input  wire [2:0]                          ext_awsize,
    input  wire [1:0]                          ext_awburst,
    input  wire                                ext_awvalid,
    output reg                                 ext_awready,

    input  wire [DATA_WIDTH-1:0]               ext_wdata,
    input  wire [DATA_WIDTH/8-1:0]             ext_wstrb,
    input  wire                                ext_wlast,
    input  wire                                ext_wvalid,
    output reg                                 ext_wready,

    output reg  [ID_WIDTH-ID_PREFIX_WIDTH-1:0] ext_bid,
    output reg  [1:0]                          ext_bresp,
    output reg                                 ext_bvalid,
    input  wire                                ext_bready,

    input  wire [ID_WIDTH-ID_PREFIX_WIDTH-1:0] ext_arid,
    input  wire [ADDR_WIDTH-1:0]               ext_araddr,
    input  wire [7:0]                          ext_arlen,
    input  wire [2:0]                          ext_arsize,
    input  wire [1:0]                          ext_arburst,
    input  wire                                ext_arvalid,
    output reg                                 ext_arready,

    output reg  [ID_WIDTH-ID_PREFIX_WIDTH-1:0] ext_rid,
    output reg  [DATA_WIDTH-1:0]               ext_rdata,
    output reg  [1:0]                          ext_rresp,
    output reg                                 ext_rlast,
    output reg                                 ext_rvalid,
    input  wire                                ext_rready,

    // Internal crossbar AXI interface (full ID_WIDTH)
    output reg  [ID_WIDTH-1:0]                 int_awid,
    output reg  [ADDR_WIDTH-1:0]               int_awaddr,
    output reg  [7:0]                          int_awlen,
    output reg  [2:0]                          int_awsize,
    output reg  [1:0]                          int_awburst,
    output reg                                 int_awvalid,
    input  wire                                int_awready,

    output reg  [DATA_WIDTH-1:0]               int_wdata,
    output reg  [DATA_WIDTH/8-1:0]             int_wstrb,
    output reg                                 int_wlast,
    output reg                                 int_wvalid,
    input  wire                                int_wready,

    input  wire [ID_WIDTH-1:0]                 int_bid,
    input  wire [1:0]                          int_bresp,
    input  wire                                int_bvalid,
    output reg                                 int_bready,

    output reg  [ID_WIDTH-1:0]                 int_arid,
    output reg  [ADDR_WIDTH-1:0]               int_araddr,
    output reg  [7:0]                          int_arlen,
    output reg  [2:0]                          int_arsize,
    output reg  [1:0]                          int_arburst,
    output reg                                 int_arvalid,
    input  wire                                int_arready,

    input  wire [ID_WIDTH-1:0]                 int_rid,
    input  wire [DATA_WIDTH-1:0]               int_rdata,
    input  wire [1:0]                          int_rresp,
    input  wire                                int_rlast,
    input  wire                                int_rvalid,
    output reg                                 int_rready,

    // Decoded slave select (from address decoder)
    output wire [NUM_SLAVES-1:0]               slave_sel_o,
    output wire                                addr_error_o
);

    localparam [ID_PREFIX_WIDTH-1:0] MY_PREFIX = MASTER_ID[ID_PREFIX_WIDTH-1:0];

    // Address decoder instance
    wire [NUM_SLAVES-1:0] aw_slave_sel;
    wire                  aw_addr_error;
    wire [NUM_SLAVES-1:0] ar_slave_sel;
    wire                  ar_addr_error;

    // Use registered decoder for AW path
    axi_addr_decoder #(
        .NUM_SLAVES (NUM_SLAVES),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_aw_decoder (
        .clk         (clk),
        .rst_n       (rst_n),
        .addr_i      (ext_awaddr),
        .slave_sel_o (aw_slave_sel),
        .addr_error_o(aw_addr_error)
    );

    // Use registered decoder for AR path
    axi_addr_decoder #(
        .NUM_SLAVES (NUM_SLAVES),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_ar_decoder (
        .clk         (clk),
        .rst_n       (rst_n),
        .addr_i      (ext_araddr),
        .slave_sel_o (ar_slave_sel),
        .addr_error_o(ar_addr_error)
    );

    assign slave_sel_o = aw_slave_sel | ar_slave_sel;
    assign addr_error_o = aw_addr_error | ar_addr_error;

    // Outstanding transaction counter
    reg [3:0] outstanding_cnt;
    wire      can_issue = (outstanding_cnt < OUTSTANDING);

    always @(posedge clk) begin
        if (!rst_n) begin
            outstanding_cnt <= 4'd0;
        end else begin
            case ({(int_awvalid && int_awready) || (int_arvalid && int_arready),
                   (int_bvalid && int_bready) || (int_rvalid && int_rready && int_rlast)})
                2'b10: outstanding_cnt <= outstanding_cnt + 4'd1;
                2'b01: outstanding_cnt <= outstanding_cnt - 4'd1;
                default: outstanding_cnt <= outstanding_cnt;
            endcase
        end
    end

    // ID prefix insertion: AW channel
    always @(posedge clk) begin
        if (!rst_n) begin
            int_awid    <= {ID_WIDTH{1'b0}};
            int_awaddr  <= {ADDR_WIDTH{1'b0}};
            int_awlen   <= 8'd0;
            int_awsize  <= 3'd0;
            int_awburst <= 2'd0;
            int_awvalid <= 1'b0;
            ext_awready <= 1'b0;
        end else begin
            ext_awready <= can_issue && !int_awvalid;

            if (ext_awvalid && ext_awready && can_issue) begin
                int_awid    <= {MY_PREFIX, ext_awid};
                int_awaddr  <= ext_awaddr;
                int_awlen   <= ext_awlen;
                int_awsize  <= ext_awsize;
                int_awburst <= ext_awburst;
                int_awvalid <= 1'b1;
            end
            if (int_awvalid && int_awready) begin
                int_awvalid <= 1'b0;
            end
        end
    end

    // W channel pass-through (registered)
    always @(posedge clk) begin
        if (!rst_n) begin
            int_wdata  <= {DATA_WIDTH{1'b0}};
            int_wstrb  <= {(DATA_WIDTH/8){1'b0}};
            int_wlast  <= 1'b0;
            int_wvalid <= 1'b0;
            ext_wready <= 1'b0;
        end else begin
            ext_wready <= !int_wvalid || int_wready;

            if (ext_wvalid && ext_wready) begin
                int_wdata  <= ext_wdata;
                int_wstrb  <= ext_wstrb;
                int_wlast  <= ext_wlast;
                int_wvalid <= 1'b1;
            end
            if (int_wvalid && int_wready && !(ext_wvalid && ext_wready)) begin
                int_wvalid <= 1'b0;
            end
        end
    end

    // B channel: strip prefix, pass back
    always @(posedge clk) begin
        if (!rst_n) begin
            ext_bid    <= {(ID_WIDTH-ID_PREFIX_WIDTH){1'b0}};
            ext_bresp  <= 2'b00;
            ext_bvalid <= 1'b0;
            int_bready <= 1'b0;
        end else begin
            int_bready <= !ext_bvalid || ext_bready;

            if (int_bvalid && int_bready) begin
                ext_bid    <= int_bid[ID_WIDTH-ID_PREFIX_WIDTH-1:0];
                ext_bresp  <= int_bresp;
                ext_bvalid <= 1'b1;
            end
            if (ext_bvalid && ext_bready && !(int_bvalid && int_bready)) begin
                ext_bvalid <= 1'b0;
            end
        end
    end

    // AR channel: prefix insertion
    always @(posedge clk) begin
        if (!rst_n) begin
            int_arid    <= {ID_WIDTH{1'b0}};
            int_araddr  <= {ADDR_WIDTH{1'b0}};
            int_arlen   <= 8'd0;
            int_arsize  <= 3'd0;
            int_arburst <= 2'd0;
            int_arvalid <= 1'b0;
            ext_arready <= 1'b0;
        end else begin
            ext_arready <= can_issue && !int_arvalid;

            if (ext_arvalid && ext_arready && can_issue) begin
                int_arid    <= {MY_PREFIX, ext_arid};
                int_araddr  <= ext_araddr;
                int_arlen   <= ext_arlen;
                int_arsize  <= ext_arsize;
                int_arburst <= ext_arburst;
                int_arvalid <= 1'b1;
            end
            if (int_arvalid && int_arready) begin
                int_arvalid <= 1'b0;
            end
        end
    end

    // R channel: strip prefix, pass back
    always @(posedge clk) begin
        if (!rst_n) begin
            ext_rid    <= {(ID_WIDTH-ID_PREFIX_WIDTH){1'b0}};
            ext_rdata  <= {DATA_WIDTH{1'b0}};
            ext_rresp  <= 2'b00;
            ext_rlast  <= 1'b0;
            ext_rvalid <= 1'b0;
            int_rready <= 1'b0;
        end else begin
            int_rready <= !ext_rvalid || ext_rready;

            if (int_rvalid && int_rready) begin
                ext_rid    <= int_rid[ID_WIDTH-ID_PREFIX_WIDTH-1:0];
                ext_rdata  <= int_rdata;
                ext_rresp  <= int_rresp;
                ext_rlast  <= int_rlast;
                ext_rvalid <= 1'b1;
            end
            if (ext_rvalid && ext_rready && !(int_rvalid && int_rready)) begin
                ext_rvalid <= 1'b0;
            end
        end
    end

endmodule
