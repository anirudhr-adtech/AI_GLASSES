`timescale 1ns/1ps
//============================================================================
// Module : ibus_axi_adapter
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Ibex instruction bus to AXI4 read-only master adapter.
//               Sequential (non-pipelined) design: one outstanding request.
//============================================================================

module ibus_axi_adapter (
    input  wire        clk,
    input  wire        rst_n,

    // Ibex instruction fetch interface
    input  wire        instr_req_i,
    output wire        instr_gnt_o,
    output wire        instr_rvalid_o,
    input  wire [31:0] instr_addr_i,
    output wire [31:0] instr_rdata_o,
    output wire        instr_err_o,

    // AXI4 Master Read Address channel
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    output wire [31:0] m_axi_araddr,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire [3:0]  m_axi_arid,

    // AXI4 Master Read Data channel
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire [3:0]  m_axi_rid,
    input  wire        m_axi_rlast
);

    // Fixed AXI parameters: single-beat, 4-byte, INCR
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = 3'b010;
    assign m_axi_arburst = 2'b01;
    assign m_axi_rready  = 1'b1;

    // FSM states
    localparam [1:0] IDLE    = 2'd0,
                     AR_WAIT = 2'd1,
                     R_WAIT  = 2'd2;

    reg [1:0]  state_r;
    reg [31:0] ar_addr_r;
    reg [3:0]  ar_id_r;
    reg        ar_valid_r;
    reg        gnt_r;
    reg        rvalid_r;
    reg [31:0] rdata_r;
    reg        rerr_r;

    assign m_axi_arvalid = ar_valid_r;
    assign m_axi_araddr  = ar_addr_r;
    assign m_axi_arid    = ar_id_r;
    assign instr_gnt_o   = gnt_r;
    assign instr_rvalid_o = rvalid_r;
    assign instr_rdata_o  = rdata_r;
    assign instr_err_o    = rerr_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            state_r    <= IDLE;
            ar_valid_r <= 1'b0;
            ar_addr_r  <= 32'd0;
            ar_id_r    <= 4'd0;
            gnt_r      <= 1'b0;
            rvalid_r   <= 1'b0;
            rdata_r    <= 32'd0;
            rerr_r     <= 1'b0;
        end else begin
            // Default pulse signals
            gnt_r    <= 1'b0;
            rvalid_r <= 1'b0;

            case (state_r)
                IDLE: begin
                    ar_valid_r <= 1'b0;
                    if (instr_req_i) begin
                        rerr_r     <= 1'b0;
                        ar_valid_r <= 1'b1;
                        ar_addr_r  <= instr_addr_i;
                        ar_id_r    <= 4'd0;
                        state_r    <= AR_WAIT;
                    end
                end

                AR_WAIT: begin
                    if (m_axi_arready) begin
                        gnt_r      <= 1'b1;
                        ar_valid_r <= 1'b0;
                        state_r    <= R_WAIT;
                    end
                end

                R_WAIT: begin
                    if (m_axi_rvalid) begin
                        rvalid_r <= 1'b1;
                        rdata_r  <= m_axi_rdata;
                        rerr_r   <= (m_axi_rresp != 2'b00);
                        state_r  <= IDLE;
                    end
                end

                default: begin
                    state_r <= IDLE;
                end
            endcase
        end
    end

endmodule
