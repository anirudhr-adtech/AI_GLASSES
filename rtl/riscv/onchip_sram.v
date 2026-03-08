`timescale 1ns/1ps
//============================================================================
// Module : onchip_sram
// Project : AI_GLASSES — RISC-V Subsystem
// Description : 512KB banked on-chip SRAM with dual AXI4 slave ports
//============================================================================

module onchip_sram #(
    parameter NUM_BANKS       = 4,
    parameter BANK_ADDR_WIDTH = 15,
    parameter DATA_WIDTH      = 32
)(
    input  wire        clk,
    input  wire        rst_n,

    // ================================================================
    // Port A — AXI4 Slave (read-only, iBus)
    // ================================================================
    input  wire [31:0] s_axi_a_araddr,
    input  wire        s_axi_a_arvalid,
    output wire        s_axi_a_arready,
    input  wire [3:0]  s_axi_a_arid,
    input  wire [7:0]  s_axi_a_arlen,
    input  wire [2:0]  s_axi_a_arsize,
    input  wire [1:0]  s_axi_a_arburst,

    output wire [31:0] s_axi_a_rdata,
    output wire        s_axi_a_rvalid,
    input  wire        s_axi_a_rready,
    output wire [1:0]  s_axi_a_rresp,
    output wire [3:0]  s_axi_a_rid,
    output wire        s_axi_a_rlast,

    // ================================================================
    // Port B — AXI4 Slave (read/write, dBus)
    // ================================================================
    // Write address
    input  wire [31:0] s_axi_b_awaddr,
    input  wire        s_axi_b_awvalid,
    output wire        s_axi_b_awready,
    input  wire [3:0]  s_axi_b_awid,
    input  wire [7:0]  s_axi_b_awlen,
    input  wire [2:0]  s_axi_b_awsize,
    input  wire [1:0]  s_axi_b_awburst,

    // Write data
    input  wire [31:0] s_axi_b_wdata,
    input  wire [3:0]  s_axi_b_wstrb,
    input  wire        s_axi_b_wvalid,
    input  wire        s_axi_b_wlast,
    output wire        s_axi_b_wready,

    // Write response
    output wire [3:0]  s_axi_b_bid,
    output wire [1:0]  s_axi_b_bresp,
    output wire        s_axi_b_bvalid,
    input  wire        s_axi_b_bready,

    // Read address
    input  wire [31:0] s_axi_b_araddr,
    input  wire        s_axi_b_arvalid,
    output wire        s_axi_b_arready,
    input  wire [3:0]  s_axi_b_arid,
    input  wire [7:0]  s_axi_b_arlen,
    input  wire [2:0]  s_axi_b_arsize,
    input  wire [1:0]  s_axi_b_arburst,

    // Read data
    output wire [31:0] s_axi_b_rdata,
    output wire        s_axi_b_rvalid,
    input  wire        s_axi_b_rready,
    output wire [1:0]  s_axi_b_rresp,
    output wire [3:0]  s_axi_b_rid,
    output wire        s_axi_b_rlast
);

    // ----------------------------------------------------------------
    // Address decode: bits [18:17] = bank, bits [16:2] = word
    // ----------------------------------------------------------------
    localparam BANK_SEL_HI = BANK_ADDR_WIDTH + 2;  // 17
    localparam BANK_SEL_LO = BANK_ADDR_WIDTH + 1;  // 16 -- wait, need 2 bits
    // For 4 banks: bits [BANK_ADDR_WIDTH+2 : BANK_ADDR_WIDTH+1] = [17:16]
    // Word offset: bits [BANK_ADDR_WIDTH:2] = [16:2] -- that's BANK_ADDR_WIDTH bits? 15 bits = [16:2]

    // ----------------------------------------------------------------
    // Bank port wires
    // ----------------------------------------------------------------
    // Port A connections (read-only)
    reg  [BANK_ADDR_WIDTH-1:0] bank_a_addr  [0:NUM_BANKS-1];
    reg                        bank_a_en    [0:NUM_BANKS-1];
    wire [DATA_WIDTH-1:0]      bank_a_rdata [0:NUM_BANKS-1];

    // Port B connections (read/write)
    reg  [BANK_ADDR_WIDTH-1:0] bank_b_addr  [0:NUM_BANKS-1];
    reg                        bank_b_en    [0:NUM_BANKS-1];
    reg                        bank_b_we    [0:NUM_BANKS-1];
    reg  [DATA_WIDTH/8-1:0]    bank_b_wstrb [0:NUM_BANKS-1];
    reg  [DATA_WIDTH-1:0]      bank_b_wdata [0:NUM_BANKS-1];
    wire [DATA_WIDTH-1:0]      bank_b_rdata [0:NUM_BANKS-1];

    // ----------------------------------------------------------------
    // Instantiate SRAM banks
    // ----------------------------------------------------------------
    genvar gi;
    generate
        for (gi = 0; gi < NUM_BANKS; gi = gi + 1) begin : gen_banks
            sram_bank #(
                .ADDR_WIDTH(BANK_ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH)
            ) u_sram_bank (
                .clk     (clk),
                .a_addr  (bank_a_addr[gi]),
                .a_en    (bank_a_en[gi]),
                .a_rdata (bank_a_rdata[gi]),
                .b_addr  (bank_b_addr[gi]),
                .b_en    (bank_b_en[gi]),
                .b_we    (bank_b_we[gi]),
                .b_wstrb (bank_b_wstrb[gi]),
                .b_wdata (bank_b_wdata[gi]),
                .b_rdata (bank_b_rdata[gi])
            );
        end
    endgenerate

    // ----------------------------------------------------------------
    // Port A — AXI4 Read-only FSM (iBus)
    // ----------------------------------------------------------------
    localparam A_IDLE  = 2'b00;
    localparam A_READ  = 2'b01;
    localparam A_RESP  = 2'b10;
    localparam A_STALL = 2'b11;

    reg [1:0]  a_state;
    reg [31:0] a_addr_latched;
    reg [3:0]  a_id;
    reg [31:0] a_rdata_r;
    reg        a_rvalid_r;
    reg        a_arready_r;
    reg [1:0]  a_bank_sel;
    reg        a_collision;

    // Port B bank selection for collision detection
    reg [1:0]  b_active_bank;
    reg        b_active;

    // Collision: both ports target the same bank in the same cycle
    wire       collision_detected = a_collision;

    always @(posedge clk) begin
        if (!rst_n) begin
            a_state     <= A_IDLE;
            a_addr_latched <= 32'd0;
            a_id        <= 4'd0;
            a_rdata_r   <= 32'd0;
            a_rvalid_r  <= 1'b0;
            a_arready_r <= 1'b1;
            a_bank_sel  <= 2'd0;
            a_collision <= 1'b0;
        end else begin
            case (a_state)
                A_IDLE: begin
                    if (s_axi_a_arvalid && a_arready_r) begin
                        a_addr_latched <= s_axi_a_araddr;
                        a_id           <= s_axi_a_arid;
                        a_bank_sel     <= s_axi_a_araddr[BANK_ADDR_WIDTH+3:BANK_ADDR_WIDTH+2];
                        a_arready_r    <= 1'b0;
                        // Check collision with port B
                        if (b_active && (s_axi_a_araddr[BANK_ADDR_WIDTH+3:BANK_ADDR_WIDTH+2] == b_active_bank)) begin
                            a_collision <= 1'b1;
                            a_state     <= A_STALL;
                        end else begin
                            a_collision <= 1'b0;
                            a_state     <= A_READ;
                        end
                    end
                end
                A_STALL: begin
                    // Port B had priority, retry after 1 cycle
                    a_collision <= 1'b0;
                    a_state     <= A_READ;
                end
                A_READ: begin
                    // Data available from SRAM after 1 cycle
                    a_rdata_r  <= bank_a_rdata[a_bank_sel];
                    a_rvalid_r <= 1'b1;
                    a_state    <= A_RESP;
                end
                A_RESP: begin
                    if (s_axi_a_rready && a_rvalid_r) begin
                        a_rvalid_r  <= 1'b0;
                        a_arready_r <= 1'b1;
                        a_state     <= A_IDLE;
                    end
                end
            endcase
        end
    end

    // Drive bank A port enables
    integer ai;
    always @(*) begin
        for (ai = 0; ai < NUM_BANKS; ai = ai + 1) begin
            bank_a_addr[ai] = a_addr_latched[BANK_ADDR_WIDTH+1:2]; // bits [16:2]
            bank_a_en[ai]   = 1'b0;
        end
        if ((a_state == A_READ) || (a_state == A_IDLE && s_axi_a_arvalid && a_arready_r && !a_collision)) begin
            if (a_state == A_IDLE) begin
                bank_a_addr[s_axi_a_araddr[BANK_ADDR_WIDTH+3:BANK_ADDR_WIDTH+2]] = s_axi_a_araddr[BANK_ADDR_WIDTH+1:2];
                bank_a_en[s_axi_a_araddr[BANK_ADDR_WIDTH+3:BANK_ADDR_WIDTH+2]]   = 1'b1;
            end else begin
                bank_a_addr[a_bank_sel] = a_addr_latched[BANK_ADDR_WIDTH+1:2];
                bank_a_en[a_bank_sel]   = 1'b1;
            end
        end
    end

    assign s_axi_a_arready = a_arready_r;
    assign s_axi_a_rdata   = a_rdata_r;
    assign s_axi_a_rvalid  = a_rvalid_r;
    assign s_axi_a_rresp   = 2'b00;
    assign s_axi_a_rid     = a_id;
    assign s_axi_a_rlast   = a_rvalid_r;

    // ----------------------------------------------------------------
    // Port B — AXI4 Read/Write FSM (dBus)
    // ----------------------------------------------------------------
    localparam B_IDLE   = 3'b000;
    localparam B_WDATA  = 3'b001;
    localparam B_WRESP  = 3'b010;
    localparam B_RREAD  = 3'b011;
    localparam B_RRESP  = 3'b100;

    reg [2:0]  b_state;
    reg [31:0] b_addr_latched;
    reg [3:0]  b_id;
    reg        b_is_write;
    reg [31:0] b_rdata_r;
    reg        b_rvalid_r;
    reg        b_arready_r;
    reg        b_awready_r;
    reg        b_wready_r;
    reg        b_bvalid_r;
    reg [3:0]  b_bid_r;
    reg [1:0]  b_bank_sel;

    always @(posedge clk) begin
        if (!rst_n) begin
            b_state      <= B_IDLE;
            b_addr_latched <= 32'd0;
            b_id         <= 4'd0;
            b_is_write   <= 1'b0;
            b_rdata_r    <= 32'd0;
            b_rvalid_r   <= 1'b0;
            b_arready_r  <= 1'b1;
            b_awready_r  <= 1'b1;
            b_wready_r   <= 1'b0;
            b_bvalid_r   <= 1'b0;
            b_bid_r      <= 4'd0;
            b_bank_sel   <= 2'd0;
            b_active_bank <= 2'd0;
            b_active     <= 1'b0;
        end else begin
            case (b_state)
                B_IDLE: begin
                    b_active <= 1'b0;
                    // Write takes priority over read if both arrive
                    if (s_axi_b_awvalid && b_awready_r) begin
                        b_addr_latched <= s_axi_b_awaddr;
                        b_id           <= s_axi_b_awid;
                        b_bank_sel     <= s_axi_b_awaddr[BANK_ADDR_WIDTH+3:BANK_ADDR_WIDTH+2];
                        b_is_write     <= 1'b1;
                        b_awready_r    <= 1'b0;
                        b_arready_r    <= 1'b0;
                        b_wready_r     <= 1'b1;
                        b_active       <= 1'b1;
                        b_active_bank  <= s_axi_b_awaddr[BANK_ADDR_WIDTH+3:BANK_ADDR_WIDTH+2];
                        b_state        <= B_WDATA;
                    end else if (s_axi_b_arvalid && b_arready_r) begin
                        b_addr_latched <= s_axi_b_araddr;
                        b_id           <= s_axi_b_arid;
                        b_bank_sel     <= s_axi_b_araddr[BANK_ADDR_WIDTH+3:BANK_ADDR_WIDTH+2];
                        b_is_write     <= 1'b0;
                        b_arready_r    <= 1'b0;
                        b_awready_r    <= 1'b0;
                        b_active       <= 1'b1;
                        b_active_bank  <= s_axi_b_araddr[BANK_ADDR_WIDTH+3:BANK_ADDR_WIDTH+2];
                        b_state        <= B_RREAD;
                    end
                end
                B_WDATA: begin
                    if (s_axi_b_wvalid && b_wready_r) begin
                        b_wready_r <= 1'b0;
                        b_bvalid_r <= 1'b1;
                        b_bid_r    <= b_id;
                        b_state    <= B_WRESP;
                    end
                end
                B_WRESP: begin
                    b_active <= 1'b0;
                    if (s_axi_b_bready && b_bvalid_r) begin
                        b_bvalid_r  <= 1'b0;
                        b_awready_r <= 1'b1;
                        b_arready_r <= 1'b1;
                        b_state     <= B_IDLE;
                    end
                end
                B_RREAD: begin
                    // Data available next cycle
                    b_rdata_r  <= bank_b_rdata[b_bank_sel];
                    b_rvalid_r <= 1'b1;
                    b_state    <= B_RRESP;
                end
                B_RRESP: begin
                    b_active <= 1'b0;
                    if (s_axi_b_rready && b_rvalid_r) begin
                        b_rvalid_r  <= 1'b0;
                        b_arready_r <= 1'b1;
                        b_awready_r <= 1'b1;
                        b_state     <= B_IDLE;
                    end
                end
                default: b_state <= B_IDLE;
            endcase
        end
    end

    // Drive bank B port enables
    integer bi;
    always @(*) begin
        for (bi = 0; bi < NUM_BANKS; bi = bi + 1) begin
            bank_b_addr[bi]  = b_addr_latched[BANK_ADDR_WIDTH+1:2];
            bank_b_en[bi]    = 1'b0;
            bank_b_we[bi]    = 1'b0;
            bank_b_wstrb[bi] = 4'b0000;
            bank_b_wdata[bi] = 32'd0;
        end
        // Write: enable bank during WDATA state
        if (b_state == B_WDATA && s_axi_b_wvalid && b_wready_r) begin
            bank_b_addr[b_bank_sel]  = b_addr_latched[BANK_ADDR_WIDTH+1:2];
            bank_b_en[b_bank_sel]    = 1'b1;
            bank_b_we[b_bank_sel]    = 1'b1;
            bank_b_wstrb[b_bank_sel] = s_axi_b_wstrb;
            bank_b_wdata[b_bank_sel] = s_axi_b_wdata;
        end
        // Read: enable bank during RREAD state
        if (b_state == B_RREAD) begin
            bank_b_addr[b_bank_sel] = b_addr_latched[BANK_ADDR_WIDTH+1:2];
            bank_b_en[b_bank_sel]   = 1'b1;
            bank_b_we[b_bank_sel]   = 1'b0;
        end
    end

    assign s_axi_b_awready = b_awready_r;
    assign s_axi_b_wready  = b_wready_r;
    assign s_axi_b_bvalid  = b_bvalid_r;
    assign s_axi_b_bid     = b_bid_r;
    assign s_axi_b_bresp   = 2'b00;

    assign s_axi_b_arready = b_arready_r;
    assign s_axi_b_rdata   = b_rdata_r;
    assign s_axi_b_rvalid  = b_rvalid_r;
    assign s_axi_b_rresp   = 2'b00;
    assign s_axi_b_rid     = b_id;
    assign s_axi_b_rlast   = b_rvalid_r;

endmodule
