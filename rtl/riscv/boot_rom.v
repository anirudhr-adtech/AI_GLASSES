`timescale 1ns/1ps
//============================================================================
// Module : boot_rom
// Project : AI_GLASSES — RISC-V Subsystem
// Description : 4KB read-only boot ROM with AXI4 slave interface
//============================================================================

module boot_rom #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 1024,
    parameter INIT_FILE  = "boot_rom.hex"
)(
    input  wire        clk,
    input  wire        rst_n,

    // AXI4 Slave — Read address channel
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    input  wire [3:0]  s_axi_arid,
    input  wire [7:0]  s_axi_arlen,
    input  wire [2:0]  s_axi_arsize,
    input  wire [1:0]  s_axi_arburst,

    // AXI4 Slave — Read data channel
    output wire [31:0] s_axi_rdata,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,
    output wire [1:0]  s_axi_rresp,
    output wire [3:0]  s_axi_rid,
    output wire        s_axi_rlast,

    // AXI4 Slave — Write address channel (writes silently ignored)
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [3:0]  s_axi_awid,
    input  wire [7:0]  s_axi_awlen,
    input  wire [2:0]  s_axi_awsize,
    input  wire [1:0]  s_axi_awburst,

    // AXI4 Slave — Write data channel
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    input  wire        s_axi_wlast,
    output wire        s_axi_wready,

    // AXI4 Slave — Write response channel
    output wire [3:0]  s_axi_bid,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready
);

    // ----------------------------------------------------------------
    // Memory array
    // ----------------------------------------------------------------
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    initial begin
        $readmemh(INIT_FILE, mem);
    end

    // ----------------------------------------------------------------
    // Read channel FSM
    // ----------------------------------------------------------------
    localparam R_IDLE = 1'b0;
    localparam R_RESP = 1'b1;

    reg        r_state;
    reg [ADDR_WIDTH-3:0] r_addr;  // word address (10 bits for 1024 depth)
    reg [3:0]  r_id;
    reg [31:0] r_data;
    reg        r_valid;
    reg        r_arready;

    always @(posedge clk) begin
        if (!rst_n) begin
            r_state   <= R_IDLE;
            r_addr    <= {(ADDR_WIDTH-2){1'b0}};
            r_id      <= 4'd0;
            r_data    <= 32'd0;
            r_valid   <= 1'b0;
            r_arready <= 1'b1;
        end else begin
            case (r_state)
                R_IDLE: begin
                    if (s_axi_arvalid && r_arready) begin
                        r_addr    <= s_axi_araddr[ADDR_WIDTH-1:2];
                        r_id      <= s_axi_arid;
                        r_data    <= mem[s_axi_araddr[ADDR_WIDTH-1:2]];
                        r_valid   <= 1'b1;
                        r_arready <= 1'b0;
                        r_state   <= R_RESP;
                    end
                end
                R_RESP: begin
                    if (s_axi_rready && r_valid) begin
                        r_valid   <= 1'b0;
                        r_arready <= 1'b1;
                        r_state   <= R_IDLE;
                    end
                end
            endcase
        end
    end

    assign s_axi_arready = r_arready;
    assign s_axi_rdata   = r_data;
    assign s_axi_rvalid  = r_valid;
    assign s_axi_rresp   = 2'b00;  // OKAY
    assign s_axi_rid     = r_id;
    assign s_axi_rlast   = r_valid; // single-beat, always last

    // ----------------------------------------------------------------
    // Write channels — accept and silently ignore
    // ----------------------------------------------------------------
    reg        w_awready;
    reg        w_wready;
    reg        w_bvalid;
    reg [3:0]  w_bid;

    localparam W_IDLE    = 2'b00;
    localparam W_WDATA   = 2'b01;
    localparam W_BRESP   = 2'b10;

    reg [1:0] w_state;

    always @(posedge clk) begin
        if (!rst_n) begin
            w_state   <= W_IDLE;
            w_awready <= 1'b1;
            w_wready  <= 1'b0;
            w_bvalid  <= 1'b0;
            w_bid     <= 4'd0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    if (s_axi_awvalid && w_awready) begin
                        w_bid     <= s_axi_awid;
                        w_awready <= 1'b0;
                        w_wready  <= 1'b1;
                        w_state   <= W_WDATA;
                    end
                end
                W_WDATA: begin
                    if (s_axi_wvalid && w_wready && s_axi_wlast) begin
                        w_wready <= 1'b0;
                        w_bvalid <= 1'b1;
                        w_state  <= W_BRESP;
                    end
                end
                W_BRESP: begin
                    if (s_axi_bready && w_bvalid) begin
                        w_bvalid  <= 1'b0;
                        w_awready <= 1'b1;
                        w_state   <= W_IDLE;
                    end
                end
                default: w_state <= W_IDLE;
            endcase
        end
    end

    assign s_axi_awready = w_awready;
    assign s_axi_wready  = w_wready;
    assign s_axi_bvalid  = w_bvalid;
    assign s_axi_bid     = w_bid;
    assign s_axi_bresp   = 2'b00;  // OKAY (writes silently ignored)

endmodule
