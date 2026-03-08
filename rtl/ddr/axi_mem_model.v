`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Module: axi_mem_model
// Description: Top-level behavioral DDR memory model with full AXI4 slave
//              interface. Instantiates all sub-modules.
//============================================================================

module axi_mem_model #(
    parameter MEM_SIZE_BYTES    = 1048576,  // 1MB
    parameter DATA_WIDTH        = 128,
    parameter ADDR_WIDTH        = 32,
    parameter ID_WIDTH          = 6,
    parameter READ_LATENCY      = 10,
    parameter WRITE_LATENCY     = 5,
    parameter BACKPRESSURE_MODE = 0,
    parameter BP_PERIOD         = 8,
    parameter BP_SEED           = 42
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // AXI4 Slave Write Address Channel
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,

    // AXI4 Slave Write Data Channel
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                   s_axi_wlast,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,

    // AXI4 Slave Write Response Channel
    output wire [ID_WIDTH-1:0]    s_axi_bid,
    output wire [1:0]             s_axi_bresp,
    output wire                   s_axi_bvalid,
    input  wire                   s_axi_bready,

    // AXI4 Slave Read Address Channel
    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,

    // AXI4 Slave Read Data Channel
    output wire [ID_WIDTH-1:0]    s_axi_rid,
    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rlast,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready,

    // Error injection
    input  wire                   error_inject_i
);

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // ---------------------------------------------------------------
    // Internal wires
    // ---------------------------------------------------------------

    // AW channel outputs
    wire                   aw_valid;
    wire [ADDR_WIDTH-1:0]  aw_addr;
    wire [7:0]             aw_len;
    wire [2:0]             aw_size;
    wire [ID_WIDTH-1:0]    aw_id;

    // W channel signals
    wire                   aw_consumed;
    wire                   wlast_done;

    // Write mem interface
    wire                   mem_wr_en;
    wire [ADDR_WIDTH-1:0]  mem_wr_addr;
    wire [DATA_WIDTH-1:0]  mem_wr_data;
    wire [STRB_WIDTH-1:0]  mem_wr_strb;

    // AR channel outputs
    wire                   ar_valid;
    wire [ADDR_WIDTH-1:0]  ar_addr;
    wire [7:0]             ar_len;
    wire [2:0]             ar_size;
    wire [ID_WIDTH-1:0]    ar_id;
    wire                   ar_ready;

    // Read mem interface
    wire                   mem_rd_en;
    wire [ADDR_WIDTH-1:0]  mem_rd_addr;
    wire [DATA_WIDTH-1:0]  mem_rd_data;

    // Backpressure
    wire                   bp_ready;

    // ---------------------------------------------------------------
    // Backpressure generator
    // ---------------------------------------------------------------
    backpressure_gen #(
        .MODE   (BACKPRESSURE_MODE),
        .PERIOD (BP_PERIOD),
        .SEED   (BP_SEED)
    ) u_bp_gen (
        .clk     (clk),
        .rst_n   (rst_n),
        .mode_i  (BACKPRESSURE_MODE[1:0]),
        .ready_o (bp_ready)
    );

    // ---------------------------------------------------------------
    // Memory array
    // ---------------------------------------------------------------
    mem_array #(
        .MEM_SIZE_BYTES (MEM_SIZE_BYTES)
    ) u_mem_array (
        .clk      (clk),
        .wr_en    (mem_wr_en),
        .wr_addr  (mem_wr_addr),
        .wr_data  (mem_wr_data),
        .wr_strb  (mem_wr_strb),
        .rd_en    (mem_rd_en),
        .rd_addr  (mem_rd_addr),
        .rd_data  (mem_rd_data)
    );

    // ---------------------------------------------------------------
    // AW Channel
    // ---------------------------------------------------------------
    axi_mem_aw_channel #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_aw_ch (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_awid     (s_axi_awid),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awlen    (s_axi_awlen),
        .s_axi_awsize   (s_axi_awsize),
        .s_axi_awburst  (s_axi_awburst),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .aw_valid_o     (aw_valid),
        .aw_addr_o      (aw_addr),
        .aw_len_o       (aw_len),
        .aw_size_o      (aw_size),
        .aw_id_o        (aw_id),
        .aw_ready_i     (aw_consumed)
    );

    // ---------------------------------------------------------------
    // W Channel
    // ---------------------------------------------------------------
    axi_mem_w_channel #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_w_ch (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wlast   (s_axi_wlast),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .aw_valid_i    (aw_valid),
        .aw_addr_i     (aw_addr),
        .aw_len_i      (aw_len),
        .aw_size_i     (aw_size),
        .aw_consumed_o (aw_consumed),
        .wlast_done_o  (wlast_done),
        .wr_en         (mem_wr_en),
        .wr_addr       (mem_wr_addr),
        .wr_data       (mem_wr_data),
        .wr_strb       (mem_wr_strb)
    );

    // ---------------------------------------------------------------
    // B Channel
    // ---------------------------------------------------------------
    axi_mem_b_channel #(
        .WRITE_LATENCY (WRITE_LATENCY),
        .ID_WIDTH      (ID_WIDTH)
    ) u_b_ch (
        .clk            (clk),
        .rst_n          (rst_n),
        .wlast_done_i   (wlast_done),
        .aw_id_i        (aw_id),
        .s_axi_bid      (s_axi_bid),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .error_inject_i (error_inject_i)
    );

    // ---------------------------------------------------------------
    // AR Channel
    // ---------------------------------------------------------------
    axi_mem_ar_channel #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_ar_ch (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_arid     (s_axi_arid),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arlen    (s_axi_arlen),
        .s_axi_arsize   (s_axi_arsize),
        .s_axi_arburst  (s_axi_arburst),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .ar_valid_o     (ar_valid),
        .ar_addr_o      (ar_addr),
        .ar_len_o       (ar_len),
        .ar_size_o      (ar_size),
        .ar_id_o        (ar_id),
        .ar_ready_i     (ar_ready)
    );

    // ---------------------------------------------------------------
    // R Channel
    // ---------------------------------------------------------------
    axi_mem_r_channel #(
        .DATA_WIDTH   (DATA_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .ID_WIDTH     (ID_WIDTH),
        .READ_LATENCY (READ_LATENCY)
    ) u_r_ch (
        .clk          (clk),
        .rst_n        (rst_n),
        .ar_valid_i   (ar_valid),
        .ar_addr_i    (ar_addr),
        .ar_len_i     (ar_len),
        .ar_size_i    (ar_size),
        .ar_id_i      (ar_id),
        .ar_ready_o   (ar_ready),
        .s_axi_rid    (s_axi_rid),
        .s_axi_rdata  (s_axi_rdata),
        .s_axi_rresp  (s_axi_rresp),
        .s_axi_rlast  (s_axi_rlast),
        .s_axi_rvalid (s_axi_rvalid),
        .s_axi_rready (s_axi_rready),
        .rd_en        (mem_rd_en),
        .rd_addr      (mem_rd_addr),
        .rd_data      (mem_rd_data)
    );

endmodule
