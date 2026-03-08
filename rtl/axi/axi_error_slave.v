`timescale 1ns/1ps
//============================================================================
// Module:      axi_error_slave
// Project:     AI_GLASSES — AXI Interconnect
// Description: Returns DECERR on any AXI4 access. Accepts AW/W channels,
//              returns BRESP=DECERR. Accepts AR, returns RRESP=DECERR with
//              RLAST. No data storage.
//============================================================================

module axi_error_slave #(
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 6,
    parameter ADDR_WIDTH = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // AXI Write Address Channel
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire                   s_axi_awvalid,
    output reg                    s_axi_awready,

    // AXI Write Data Channel
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                   s_axi_wlast,
    input  wire                   s_axi_wvalid,
    output reg                    s_axi_wready,

    // AXI Write Response Channel
    output reg  [ID_WIDTH-1:0]    s_axi_bid,
    output reg  [1:0]             s_axi_bresp,
    output reg                    s_axi_bvalid,
    input  wire                   s_axi_bready,

    // AXI Read Address Channel
    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire                   s_axi_arvalid,
    output reg                    s_axi_arready,

    // AXI Read Data Channel
    output reg  [ID_WIDTH-1:0]    s_axi_rid,
    output reg  [DATA_WIDTH-1:0]  s_axi_rdata,
    output reg  [1:0]             s_axi_rresp,
    output reg                    s_axi_rlast,
    output reg                    s_axi_rvalid,
    input  wire                   s_axi_rready
);

    localparam RESP_DECERR = 2'b11;

    // Write FSM states
    localparam W_IDLE     = 2'd0;
    localparam W_DATA     = 2'd1;
    localparam W_RESP     = 2'd2;

    // Read FSM states
    localparam R_IDLE     = 2'd0;
    localparam R_DATA     = 2'd1;

    reg [1:0] wr_state;
    reg [1:0] rd_state;
    reg [ID_WIDTH-1:0] wr_id;
    reg [ID_WIDTH-1:0] rd_id;
    reg [7:0] rd_beat_cnt;
    reg [7:0] rd_len;

    // Write FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_state      <= W_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bid     <= {ID_WIDTH{1'b0}};
            s_axi_bresp   <= 2'b00;
            wr_id         <= {ID_WIDTH{1'b0}};
        end else begin
            case (wr_state)
                W_IDLE: begin
                    s_axi_bvalid  <= 1'b0;
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b0;
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_id         <= s_axi_awid;
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b1;
                        wr_state      <= W_DATA;
                    end
                end
                W_DATA: begin
                    if (s_axi_wvalid && s_axi_wready && s_axi_wlast) begin
                        s_axi_wready <= 1'b0;
                        s_axi_bid    <= wr_id;
                        s_axi_bresp  <= RESP_DECERR;
                        s_axi_bvalid <= 1'b1;
                        wr_state     <= W_RESP;
                    end
                end
                W_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state     <= W_IDLE;
                    end
                end
                default: wr_state <= W_IDLE;
            endcase
        end
    end

    // Read FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_state      <= R_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rid     <= {ID_WIDTH{1'b0}};
            s_axi_rdata   <= {DATA_WIDTH{1'b0}};
            s_axi_rresp   <= 2'b00;
            s_axi_rlast   <= 1'b0;
            rd_id         <= {ID_WIDTH{1'b0}};
            rd_beat_cnt   <= 8'd0;
            rd_len        <= 8'd0;
        end else begin
            case (rd_state)
                R_IDLE: begin
                    s_axi_rvalid  <= 1'b0;
                    s_axi_rlast   <= 1'b0;
                    s_axi_arready <= 1'b1;
                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_id         <= s_axi_arid;
                        rd_len        <= s_axi_arlen;
                        rd_beat_cnt   <= 8'd0;
                        s_axi_arready <= 1'b0;
                        s_axi_rid     <= s_axi_arid;
                        s_axi_rdata   <= {DATA_WIDTH{1'b0}};
                        s_axi_rresp   <= RESP_DECERR;
                        s_axi_rvalid  <= 1'b1;
                        s_axi_rlast   <= (s_axi_arlen == 8'd0) ? 1'b1 : 1'b0;
                        rd_state      <= R_DATA;
                    end
                end
                R_DATA: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        if (s_axi_rlast) begin
                            s_axi_rvalid <= 1'b0;
                            s_axi_rlast  <= 1'b0;
                            rd_state     <= R_IDLE;
                        end else begin
                            rd_beat_cnt <= rd_beat_cnt + 8'd1;
                            if ((rd_beat_cnt + 8'd1) == rd_len) begin
                                s_axi_rlast <= 1'b1;
                            end
                        end
                    end
                end
                default: rd_state <= R_IDLE;
            endcase
        end
    end

endmodule
