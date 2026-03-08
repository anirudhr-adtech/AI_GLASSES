`timescale 1ns/1ps
//============================================================================
// Module : axilite_interconnect
// Project : AI_GLASSES — RISC-V Subsystem
// Description : AXI4-Lite crossbar: 1 master -> 9 slaves. Single
//               transaction at a time. Returns SLVERR for unmapped.
//============================================================================

module axilite_interconnect #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter NUM_SLAVES = 9
)(
    input  wire        clk,
    input  wire        rst_n,

    // ================================================================
    // AXI-Lite Slave port (from master / bridge)
    // ================================================================
    input  wire [ADDR_WIDTH-1:0]   s_axil_awaddr,
    input  wire                    s_axil_awvalid,
    output wire                    s_axil_awready,
    input  wire [DATA_WIDTH-1:0]   s_axil_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axil_wstrb,
    input  wire                    s_axil_wvalid,
    output wire                    s_axil_wready,
    output wire [1:0]              s_axil_bresp,
    output wire                    s_axil_bvalid,
    input  wire                    s_axil_bready,
    input  wire [ADDR_WIDTH-1:0]   s_axil_araddr,
    input  wire                    s_axil_arvalid,
    output wire                    s_axil_arready,
    output wire [DATA_WIDTH-1:0]   s_axil_rdata,
    output wire [1:0]              s_axil_rresp,
    output wire                    s_axil_rvalid,
    input  wire                    s_axil_rready,

    // ================================================================
    // AXI-Lite Master port 0 — UART (0x2000_0000)
    // ================================================================
    output wire [7:0]              m_axil_0_awaddr,
    output wire                    m_axil_0_awvalid,
    input  wire                    m_axil_0_awready,
    output wire [DATA_WIDTH-1:0]   m_axil_0_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axil_0_wstrb,
    output wire                    m_axil_0_wvalid,
    input  wire                    m_axil_0_wready,
    input  wire [1:0]              m_axil_0_bresp,
    input  wire                    m_axil_0_bvalid,
    output wire                    m_axil_0_bready,
    output wire [7:0]              m_axil_0_araddr,
    output wire                    m_axil_0_arvalid,
    input  wire                    m_axil_0_arready,
    input  wire [DATA_WIDTH-1:0]   m_axil_0_rdata,
    input  wire [1:0]              m_axil_0_rresp,
    input  wire                    m_axil_0_rvalid,
    output wire                    m_axil_0_rready,

    // ================================================================
    // AXI-Lite Master port 1 — Timer (0x2000_0100)
    // ================================================================
    output wire [7:0]              m_axil_1_awaddr,
    output wire                    m_axil_1_awvalid,
    input  wire                    m_axil_1_awready,
    output wire [DATA_WIDTH-1:0]   m_axil_1_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axil_1_wstrb,
    output wire                    m_axil_1_wvalid,
    input  wire                    m_axil_1_wready,
    input  wire [1:0]              m_axil_1_bresp,
    input  wire                    m_axil_1_bvalid,
    output wire                    m_axil_1_bready,
    output wire [7:0]              m_axil_1_araddr,
    output wire                    m_axil_1_arvalid,
    input  wire                    m_axil_1_arready,
    input  wire [DATA_WIDTH-1:0]   m_axil_1_rdata,
    input  wire [1:0]              m_axil_1_rresp,
    input  wire                    m_axil_1_rvalid,
    output wire                    m_axil_1_rready,

    // ================================================================
    // AXI-Lite Master port 2 — IRQ Controller (0x2000_0200)
    // ================================================================
    output wire [7:0]              m_axil_2_awaddr,
    output wire                    m_axil_2_awvalid,
    input  wire                    m_axil_2_awready,
    output wire [DATA_WIDTH-1:0]   m_axil_2_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axil_2_wstrb,
    output wire                    m_axil_2_wvalid,
    input  wire                    m_axil_2_wready,
    input  wire [1:0]              m_axil_2_bresp,
    input  wire                    m_axil_2_bvalid,
    output wire                    m_axil_2_bready,
    output wire [7:0]              m_axil_2_araddr,
    output wire                    m_axil_2_arvalid,
    input  wire                    m_axil_2_arready,
    input  wire [DATA_WIDTH-1:0]   m_axil_2_rdata,
    input  wire [1:0]              m_axil_2_rresp,
    input  wire                    m_axil_2_rvalid,
    output wire                    m_axil_2_rready,

    // ================================================================
    // AXI-Lite Master port 3 — GPIO (0x2000_0300)
    // ================================================================
    output wire [7:0]              m_axil_3_awaddr,
    output wire                    m_axil_3_awvalid,
    input  wire                    m_axil_3_awready,
    output wire [DATA_WIDTH-1:0]   m_axil_3_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axil_3_wstrb,
    output wire                    m_axil_3_wvalid,
    input  wire                    m_axil_3_wready,
    input  wire [1:0]              m_axil_3_bresp,
    input  wire                    m_axil_3_bvalid,
    output wire                    m_axil_3_bready,
    output wire [7:0]              m_axil_3_araddr,
    output wire                    m_axil_3_arvalid,
    input  wire                    m_axil_3_arready,
    input  wire [DATA_WIDTH-1:0]   m_axil_3_rdata,
    input  wire [1:0]              m_axil_3_rresp,
    input  wire                    m_axil_3_rvalid,
    output wire                    m_axil_3_rready,

    // ================================================================
    // AXI-Lite Master port 4 — Camera Ctrl (0x2000_0400)
    // ================================================================
    output wire [7:0]              m_axil_4_awaddr,
    output wire                    m_axil_4_awvalid,
    input  wire                    m_axil_4_awready,
    output wire [DATA_WIDTH-1:0]   m_axil_4_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axil_4_wstrb,
    output wire                    m_axil_4_wvalid,
    input  wire                    m_axil_4_wready,
    input  wire [1:0]              m_axil_4_bresp,
    input  wire                    m_axil_4_bvalid,
    output wire                    m_axil_4_bready,
    output wire [7:0]              m_axil_4_araddr,
    output wire                    m_axil_4_arvalid,
    input  wire                    m_axil_4_arready,
    input  wire [DATA_WIDTH-1:0]   m_axil_4_rdata,
    input  wire [1:0]              m_axil_4_rresp,
    input  wire                    m_axil_4_rvalid,
    output wire                    m_axil_4_rready,

    // ================================================================
    // AXI-Lite Master port 5 — Audio Ctrl (0x2000_0500)
    // ================================================================
    output wire [7:0]              m_axil_5_awaddr,
    output wire                    m_axil_5_awvalid,
    input  wire                    m_axil_5_awready,
    output wire [DATA_WIDTH-1:0]   m_axil_5_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axil_5_wstrb,
    output wire                    m_axil_5_wvalid,
    input  wire                    m_axil_5_wready,
    input  wire [1:0]              m_axil_5_bresp,
    input  wire                    m_axil_5_bvalid,
    output wire                    m_axil_5_bready,
    output wire [7:0]              m_axil_5_araddr,
    output wire                    m_axil_5_arvalid,
    input  wire                    m_axil_5_arready,
    input  wire [DATA_WIDTH-1:0]   m_axil_5_rdata,
    input  wire [1:0]              m_axil_5_rresp,
    input  wire                    m_axil_5_rvalid,
    output wire                    m_axil_5_rready,

    // ================================================================
    // AXI-Lite Master port 6 — I2C Master (0x2000_0600)
    // ================================================================
    output wire [7:0]              m_axil_6_awaddr,
    output wire                    m_axil_6_awvalid,
    input  wire                    m_axil_6_awready,
    output wire [DATA_WIDTH-1:0]   m_axil_6_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axil_6_wstrb,
    output wire                    m_axil_6_wvalid,
    input  wire                    m_axil_6_wready,
    input  wire [1:0]              m_axil_6_bresp,
    input  wire                    m_axil_6_bvalid,
    output wire                    m_axil_6_bready,
    output wire [7:0]              m_axil_6_araddr,
    output wire                    m_axil_6_arvalid,
    input  wire                    m_axil_6_arready,
    input  wire [DATA_WIDTH-1:0]   m_axil_6_rdata,
    input  wire [1:0]              m_axil_6_rresp,
    input  wire                    m_axil_6_rvalid,
    output wire                    m_axil_6_rready,

    // ================================================================
    // AXI-Lite Master port 7 — SPI Master (0x2000_0700)
    // ================================================================
    output wire [7:0]              m_axil_7_awaddr,
    output wire                    m_axil_7_awvalid,
    input  wire                    m_axil_7_awready,
    output wire [DATA_WIDTH-1:0]   m_axil_7_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axil_7_wstrb,
    output wire                    m_axil_7_wvalid,
    input  wire                    m_axil_7_wready,
    input  wire [1:0]              m_axil_7_bresp,
    input  wire                    m_axil_7_bvalid,
    output wire                    m_axil_7_bready,
    output wire [7:0]              m_axil_7_araddr,
    output wire                    m_axil_7_arvalid,
    input  wire                    m_axil_7_arready,
    input  wire [DATA_WIDTH-1:0]   m_axil_7_rdata,
    input  wire [1:0]              m_axil_7_rresp,
    input  wire                    m_axil_7_rvalid,
    output wire                    m_axil_7_rready,

    // ================================================================
    // AXI-Lite Master port 8 — NPU Regfile (0x2000_0800)
    // ================================================================
    output wire [7:0]              m_axil_8_awaddr,
    output wire                    m_axil_8_awvalid,
    input  wire                    m_axil_8_awready,
    output wire [DATA_WIDTH-1:0]   m_axil_8_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axil_8_wstrb,
    output wire                    m_axil_8_wvalid,
    input  wire                    m_axil_8_wready,
    input  wire [1:0]              m_axil_8_bresp,
    input  wire                    m_axil_8_bvalid,
    output wire                    m_axil_8_bready,
    output wire [7:0]              m_axil_8_araddr,
    output wire                    m_axil_8_arvalid,
    input  wire                    m_axil_8_arready,
    input  wire [DATA_WIDTH-1:0]   m_axil_8_rdata,
    input  wire [1:0]              m_axil_8_rresp,
    input  wire                    m_axil_8_rvalid,
    output wire                    m_axil_8_rready
);

    // ================================================================
    // Address decoder
    // ================================================================
    wire [3:0] dec_slave_sel;
    wire       dec_error;

    riscv_axilite_addr_decoder #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .NUM_SLAVES(NUM_SLAVES)
    ) u_addr_dec (
        .clk           (clk),
        .rst_n         (rst_n),
        .addr_i        (32'd0),     // Not used for registered path; we decode inline
        .slave_sel_o   (dec_slave_sel),
        .decode_error_o(dec_error)
    );

    // ================================================================
    // FSM
    // ================================================================
    localparam [2:0] ST_IDLE     = 3'd0,
                     ST_WR_ADDR  = 3'd1,
                     ST_WR_DATA  = 3'd2,
                     ST_WR_RESP  = 3'd3,
                     ST_RD_ADDR  = 3'd4,
                     ST_RD_RESP  = 3'd5,
                     ST_ERR_RESP = 3'd6;

    reg [2:0]              state_r;
    reg [3:0]              tgt_slave_r;
    reg                    is_write_r;
    reg                    decode_err_r;

    // Latched address/data
    reg [ADDR_WIDTH-1:0]   lat_addr_r;
    reg [DATA_WIDTH-1:0]   lat_wdata_r;
    reg [DATA_WIDTH/8-1:0] lat_wstrb_r;

    // Slave port output registers
    reg                    s_awready_r;
    reg                    s_wready_r;
    reg [1:0]              s_bresp_r;
    reg                    s_bvalid_r;
    reg                    s_arready_r;
    reg [DATA_WIDTH-1:0]   s_rdata_r;
    reg [1:0]              s_rresp_r;
    reg                    s_rvalid_r;

    // Master port output registers (shared bus, active for one slave at a time)
    reg [7:0]              m_awaddr_r;
    reg                    m_awvalid_r [0:NUM_SLAVES-1];
    reg [DATA_WIDTH-1:0]   m_wdata_r;
    reg [DATA_WIDTH/8-1:0] m_wstrb_r;
    reg                    m_wvalid_r  [0:NUM_SLAVES-1];
    reg                    m_bready_r  [0:NUM_SLAVES-1];
    reg [7:0]              m_araddr_r;
    reg                    m_arvalid_r [0:NUM_SLAVES-1];
    reg                    m_rready_r  [0:NUM_SLAVES-1];

    // Wire arrays for slave responses
    wire                   slv_awready [0:NUM_SLAVES-1];
    wire                   slv_wready  [0:NUM_SLAVES-1];
    wire [1:0]             slv_bresp   [0:NUM_SLAVES-1];
    wire                   slv_bvalid  [0:NUM_SLAVES-1];
    wire                   slv_arready [0:NUM_SLAVES-1];
    wire [DATA_WIDTH-1:0]  slv_rdata   [0:NUM_SLAVES-1];
    wire [1:0]             slv_rresp   [0:NUM_SLAVES-1];
    wire                   slv_rvalid  [0:NUM_SLAVES-1];

    // Map port wires
    assign slv_awready[0] = m_axil_0_awready; assign slv_wready[0] = m_axil_0_wready;
    assign slv_bresp[0]   = m_axil_0_bresp;   assign slv_bvalid[0] = m_axil_0_bvalid;
    assign slv_arready[0] = m_axil_0_arready;
    assign slv_rdata[0]   = m_axil_0_rdata;   assign slv_rresp[0]  = m_axil_0_rresp;
    assign slv_rvalid[0]  = m_axil_0_rvalid;

    assign slv_awready[1] = m_axil_1_awready; assign slv_wready[1] = m_axil_1_wready;
    assign slv_bresp[1]   = m_axil_1_bresp;   assign slv_bvalid[1] = m_axil_1_bvalid;
    assign slv_arready[1] = m_axil_1_arready;
    assign slv_rdata[1]   = m_axil_1_rdata;   assign slv_rresp[1]  = m_axil_1_rresp;
    assign slv_rvalid[1]  = m_axil_1_rvalid;

    assign slv_awready[2] = m_axil_2_awready; assign slv_wready[2] = m_axil_2_wready;
    assign slv_bresp[2]   = m_axil_2_bresp;   assign slv_bvalid[2] = m_axil_2_bvalid;
    assign slv_arready[2] = m_axil_2_arready;
    assign slv_rdata[2]   = m_axil_2_rdata;   assign slv_rresp[2]  = m_axil_2_rresp;
    assign slv_rvalid[2]  = m_axil_2_rvalid;

    assign slv_awready[3] = m_axil_3_awready; assign slv_wready[3] = m_axil_3_wready;
    assign slv_bresp[3]   = m_axil_3_bresp;   assign slv_bvalid[3] = m_axil_3_bvalid;
    assign slv_arready[3] = m_axil_3_arready;
    assign slv_rdata[3]   = m_axil_3_rdata;   assign slv_rresp[3]  = m_axil_3_rresp;
    assign slv_rvalid[3]  = m_axil_3_rvalid;

    assign slv_awready[4] = m_axil_4_awready; assign slv_wready[4] = m_axil_4_wready;
    assign slv_bresp[4]   = m_axil_4_bresp;   assign slv_bvalid[4] = m_axil_4_bvalid;
    assign slv_arready[4] = m_axil_4_arready;
    assign slv_rdata[4]   = m_axil_4_rdata;   assign slv_rresp[4]  = m_axil_4_rresp;
    assign slv_rvalid[4]  = m_axil_4_rvalid;

    assign slv_awready[5] = m_axil_5_awready; assign slv_wready[5] = m_axil_5_wready;
    assign slv_bresp[5]   = m_axil_5_bresp;   assign slv_bvalid[5] = m_axil_5_bvalid;
    assign slv_arready[5] = m_axil_5_arready;
    assign slv_rdata[5]   = m_axil_5_rdata;   assign slv_rresp[5]  = m_axil_5_rresp;
    assign slv_rvalid[5]  = m_axil_5_rvalid;

    assign slv_awready[6] = m_axil_6_awready; assign slv_wready[6] = m_axil_6_wready;
    assign slv_bresp[6]   = m_axil_6_bresp;   assign slv_bvalid[6] = m_axil_6_bvalid;
    assign slv_arready[6] = m_axil_6_arready;
    assign slv_rdata[6]   = m_axil_6_rdata;   assign slv_rresp[6]  = m_axil_6_rresp;
    assign slv_rvalid[6]  = m_axil_6_rvalid;

    assign slv_awready[7] = m_axil_7_awready; assign slv_wready[7] = m_axil_7_wready;
    assign slv_bresp[7]   = m_axil_7_bresp;   assign slv_bvalid[7] = m_axil_7_bvalid;
    assign slv_arready[7] = m_axil_7_arready;
    assign slv_rdata[7]   = m_axil_7_rdata;   assign slv_rresp[7]  = m_axil_7_rresp;
    assign slv_rvalid[7]  = m_axil_7_rvalid;

    assign slv_awready[8] = m_axil_8_awready; assign slv_wready[8] = m_axil_8_wready;
    assign slv_bresp[8]   = m_axil_8_bresp;   assign slv_bvalid[8] = m_axil_8_bvalid;
    assign slv_arready[8] = m_axil_8_arready;
    assign slv_rdata[8]   = m_axil_8_rdata;   assign slv_rresp[8]  = m_axil_8_rresp;
    assign slv_rvalid[8]  = m_axil_8_rvalid;

    // Inline address decode (4-bit slave index for up to 9 slaves)
    wire [3:0] addr_decode_wr;
    wire       addr_err_wr;
    wire [3:0] addr_decode_rd;
    wire       addr_err_rd;

    assign addr_decode_wr = s_axil_awaddr[11:8];
    assign addr_err_wr    = !(s_axil_awaddr[31:16] == 16'h2000 && s_axil_awaddr[15:8] < 8'd9);
    assign addr_decode_rd = s_axil_araddr[11:8];
    assign addr_err_rd    = !(s_axil_araddr[31:16] == 16'h2000 && s_axil_araddr[15:8] < 8'd9);

    // ================================================================
    // Main FSM
    // ================================================================
    integer fi;
    always @(posedge clk) begin
        if (!rst_n) begin
            state_r      <= ST_IDLE;
            tgt_slave_r  <= 3'd0;
            is_write_r   <= 1'b0;
            decode_err_r <= 1'b0;
            lat_addr_r   <= {ADDR_WIDTH{1'b0}};
            lat_wdata_r  <= {DATA_WIDTH{1'b0}};
            lat_wstrb_r  <= {(DATA_WIDTH/8){1'b0}};
            s_awready_r  <= 1'b0;
            s_wready_r   <= 1'b0;
            s_bresp_r    <= 2'b00;
            s_bvalid_r   <= 1'b0;
            s_arready_r  <= 1'b0;
            s_rdata_r    <= {DATA_WIDTH{1'b0}};
            s_rresp_r    <= 2'b00;
            s_rvalid_r   <= 1'b0;
            m_awaddr_r   <= 8'd0;
            m_wdata_r    <= {DATA_WIDTH{1'b0}};
            m_wstrb_r    <= {(DATA_WIDTH/8){1'b0}};
            m_araddr_r   <= 8'd0;
            for (fi = 0; fi < NUM_SLAVES; fi = fi + 1) begin
                m_awvalid_r[fi] <= 1'b0;
                m_wvalid_r[fi]  <= 1'b0;
                m_bready_r[fi]  <= 1'b0;
                m_arvalid_r[fi] <= 1'b0;
                m_rready_r[fi]  <= 1'b0;
            end
        end else begin
            // Default deasserts
            s_awready_r <= 1'b0;
            s_wready_r  <= 1'b0;
            s_arready_r <= 1'b0;

            // Clear response valids on handshake
            if (s_bvalid_r && s_axil_bready)
                s_bvalid_r <= 1'b0;
            if (s_rvalid_r && s_axil_rready)
                s_rvalid_r <= 1'b0;

            case (state_r)
                ST_IDLE: begin
                    // Write has priority
                    if (s_axil_awvalid && s_axil_wvalid) begin
                        s_awready_r  <= 1'b1;
                        s_wready_r   <= 1'b1;
                        lat_addr_r   <= s_axil_awaddr;
                        lat_wdata_r  <= s_axil_wdata;
                        lat_wstrb_r  <= s_axil_wstrb;
                        is_write_r   <= 1'b1;
                        tgt_slave_r  <= addr_decode_wr;
                        decode_err_r <= addr_err_wr;
                        if (addr_err_wr)
                            state_r <= ST_ERR_RESP;
                        else
                            state_r <= ST_WR_ADDR;
                    end else if (s_axil_arvalid) begin
                        s_arready_r  <= 1'b1;
                        lat_addr_r   <= s_axil_araddr;
                        is_write_r   <= 1'b0;
                        tgt_slave_r  <= addr_decode_rd;
                        decode_err_r <= addr_err_rd;
                        if (addr_err_rd)
                            state_r <= ST_ERR_RESP;
                        else
                            state_r <= ST_RD_ADDR;
                    end
                end

                ST_WR_ADDR: begin
                    m_awaddr_r                  <= lat_addr_r[7:0];
                    m_awvalid_r[tgt_slave_r]    <= 1'b1;
                    m_wdata_r                   <= lat_wdata_r;
                    m_wstrb_r                   <= lat_wstrb_r;
                    m_wvalid_r[tgt_slave_r]     <= 1'b1;
                    state_r <= ST_WR_DATA;
                end

                ST_WR_DATA: begin
                    if (slv_awready[tgt_slave_r] && m_awvalid_r[tgt_slave_r])
                        m_awvalid_r[tgt_slave_r] <= 1'b0;
                    if (slv_wready[tgt_slave_r] && m_wvalid_r[tgt_slave_r])
                        m_wvalid_r[tgt_slave_r] <= 1'b0;

                    if ((!m_awvalid_r[tgt_slave_r] || slv_awready[tgt_slave_r]) &&
                        (!m_wvalid_r[tgt_slave_r]  || slv_wready[tgt_slave_r])) begin
                        m_awvalid_r[tgt_slave_r] <= 1'b0;
                        m_wvalid_r[tgt_slave_r]  <= 1'b0;
                        m_bready_r[tgt_slave_r]  <= 1'b1;
                        state_r <= ST_WR_RESP;
                    end
                end

                ST_WR_RESP: begin
                    if (slv_bvalid[tgt_slave_r]) begin
                        m_bready_r[tgt_slave_r] <= 1'b0;
                        s_bresp_r  <= slv_bresp[tgt_slave_r];
                        s_bvalid_r <= 1'b1;
                        state_r    <= ST_IDLE;
                    end
                end

                ST_RD_ADDR: begin
                    m_araddr_r                  <= lat_addr_r[7:0];
                    m_arvalid_r[tgt_slave_r]    <= 1'b1;
                    state_r <= ST_RD_RESP;
                end

                ST_RD_RESP: begin
                    if (slv_arready[tgt_slave_r] && m_arvalid_r[tgt_slave_r])
                        m_arvalid_r[tgt_slave_r] <= 1'b0;

                    if (!m_arvalid_r[tgt_slave_r] || slv_arready[tgt_slave_r]) begin
                        m_arvalid_r[tgt_slave_r] <= 1'b0;
                        m_rready_r[tgt_slave_r]  <= 1'b1;
                    end

                    if (slv_rvalid[tgt_slave_r] && m_rready_r[tgt_slave_r]) begin
                        m_rready_r[tgt_slave_r] <= 1'b0;
                        s_rdata_r  <= slv_rdata[tgt_slave_r];
                        s_rresp_r  <= slv_rresp[tgt_slave_r];
                        s_rvalid_r <= 1'b1;
                        state_r    <= ST_IDLE;
                    end
                end

                ST_ERR_RESP: begin
                    if (is_write_r) begin
                        s_bresp_r  <= 2'b10;  // SLVERR
                        s_bvalid_r <= 1'b1;
                    end else begin
                        s_rdata_r  <= {DATA_WIDTH{1'b0}};
                        s_rresp_r  <= 2'b10;  // SLVERR
                        s_rvalid_r <= 1'b1;
                    end
                    state_r <= ST_IDLE;
                end

                default: state_r <= ST_IDLE;
            endcase
        end
    end

    // ================================================================
    // Output assignments — slave port
    // ================================================================
    assign s_axil_awready = s_awready_r;
    assign s_axil_wready  = s_wready_r;
    assign s_axil_bresp   = s_bresp_r;
    assign s_axil_bvalid  = s_bvalid_r;
    assign s_axil_arready = s_arready_r;
    assign s_axil_rdata   = s_rdata_r;
    assign s_axil_rresp   = s_rresp_r;
    assign s_axil_rvalid  = s_rvalid_r;

    // ================================================================
    // Output assignments — master ports (shared data, per-slave valid)
    // ================================================================
    assign m_axil_0_awaddr  = m_awaddr_r;  assign m_axil_0_awvalid = m_awvalid_r[0];
    assign m_axil_0_wdata   = m_wdata_r;   assign m_axil_0_wstrb   = m_wstrb_r;
    assign m_axil_0_wvalid  = m_wvalid_r[0];
    assign m_axil_0_bready  = m_bready_r[0];
    assign m_axil_0_araddr  = m_araddr_r;  assign m_axil_0_arvalid = m_arvalid_r[0];
    assign m_axil_0_rready  = m_rready_r[0];

    assign m_axil_1_awaddr  = m_awaddr_r;  assign m_axil_1_awvalid = m_awvalid_r[1];
    assign m_axil_1_wdata   = m_wdata_r;   assign m_axil_1_wstrb   = m_wstrb_r;
    assign m_axil_1_wvalid  = m_wvalid_r[1];
    assign m_axil_1_bready  = m_bready_r[1];
    assign m_axil_1_araddr  = m_araddr_r;  assign m_axil_1_arvalid = m_arvalid_r[1];
    assign m_axil_1_rready  = m_rready_r[1];

    assign m_axil_2_awaddr  = m_awaddr_r;  assign m_axil_2_awvalid = m_awvalid_r[2];
    assign m_axil_2_wdata   = m_wdata_r;   assign m_axil_2_wstrb   = m_wstrb_r;
    assign m_axil_2_wvalid  = m_wvalid_r[2];
    assign m_axil_2_bready  = m_bready_r[2];
    assign m_axil_2_araddr  = m_araddr_r;  assign m_axil_2_arvalid = m_arvalid_r[2];
    assign m_axil_2_rready  = m_rready_r[2];

    assign m_axil_3_awaddr  = m_awaddr_r;  assign m_axil_3_awvalid = m_awvalid_r[3];
    assign m_axil_3_wdata   = m_wdata_r;   assign m_axil_3_wstrb   = m_wstrb_r;
    assign m_axil_3_wvalid  = m_wvalid_r[3];
    assign m_axil_3_bready  = m_bready_r[3];
    assign m_axil_3_araddr  = m_araddr_r;  assign m_axil_3_arvalid = m_arvalid_r[3];
    assign m_axil_3_rready  = m_rready_r[3];

    assign m_axil_4_awaddr  = m_awaddr_r;  assign m_axil_4_awvalid = m_awvalid_r[4];
    assign m_axil_4_wdata   = m_wdata_r;   assign m_axil_4_wstrb   = m_wstrb_r;
    assign m_axil_4_wvalid  = m_wvalid_r[4];
    assign m_axil_4_bready  = m_bready_r[4];
    assign m_axil_4_araddr  = m_araddr_r;  assign m_axil_4_arvalid = m_arvalid_r[4];
    assign m_axil_4_rready  = m_rready_r[4];

    assign m_axil_5_awaddr  = m_awaddr_r;  assign m_axil_5_awvalid = m_awvalid_r[5];
    assign m_axil_5_wdata   = m_wdata_r;   assign m_axil_5_wstrb   = m_wstrb_r;
    assign m_axil_5_wvalid  = m_wvalid_r[5];
    assign m_axil_5_bready  = m_bready_r[5];
    assign m_axil_5_araddr  = m_araddr_r;  assign m_axil_5_arvalid = m_arvalid_r[5];
    assign m_axil_5_rready  = m_rready_r[5];

    assign m_axil_6_awaddr  = m_awaddr_r;  assign m_axil_6_awvalid = m_awvalid_r[6];
    assign m_axil_6_wdata   = m_wdata_r;   assign m_axil_6_wstrb   = m_wstrb_r;
    assign m_axil_6_wvalid  = m_wvalid_r[6];
    assign m_axil_6_bready  = m_bready_r[6];
    assign m_axil_6_araddr  = m_araddr_r;  assign m_axil_6_arvalid = m_arvalid_r[6];
    assign m_axil_6_rready  = m_rready_r[6];

    assign m_axil_7_awaddr  = m_awaddr_r;  assign m_axil_7_awvalid = m_awvalid_r[7];
    assign m_axil_7_wdata   = m_wdata_r;   assign m_axil_7_wstrb   = m_wstrb_r;
    assign m_axil_7_wvalid  = m_wvalid_r[7];
    assign m_axil_7_bready  = m_bready_r[7];
    assign m_axil_7_araddr  = m_araddr_r;  assign m_axil_7_arvalid = m_arvalid_r[7];
    assign m_axil_7_rready  = m_rready_r[7];

    assign m_axil_8_awaddr  = m_awaddr_r;  assign m_axil_8_awvalid = m_awvalid_r[8];
    assign m_axil_8_wdata   = m_wdata_r;   assign m_axil_8_wstrb   = m_wstrb_r;
    assign m_axil_8_wvalid  = m_wvalid_r[8];
    assign m_axil_8_bready  = m_bready_r[8];
    assign m_axil_8_araddr  = m_araddr_r;  assign m_axil_8_arvalid = m_arvalid_r[8];
    assign m_axil_8_rready  = m_rready_r[8];

endmodule
