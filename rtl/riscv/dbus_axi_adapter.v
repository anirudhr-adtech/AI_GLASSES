`timescale 1ns/1ps
//============================================================================
// Module : dbus_axi_adapter
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Ibex data bus to AXI4 full master adapter (read + write).
//               Supports 1 outstanding transaction.
//============================================================================

module dbus_axi_adapter (
    input  wire        clk,
    input  wire        rst_n,

    // Ibex data interface
    input  wire        data_req_i,
    output wire        data_gnt_o,
    output wire        data_rvalid_o,
    input  wire        data_we_i,
    input  wire [3:0]  data_be_i,
    input  wire [31:0] data_addr_i,
    input  wire [31:0] data_wdata_i,
    output wire [31:0] data_rdata_o,
    output wire        data_err_o,

    // AXI4 Master Write Address channel
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    output wire [31:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output wire [3:0]  m_axi_awid,

    // AXI4 Master Write Data channel
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,
    output wire [31:0] m_axi_wdata,
    output wire [3:0]  m_axi_wstrb,
    output wire        m_axi_wlast,

    // AXI4 Master Write Response channel
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,
    input  wire [1:0]  m_axi_bresp,
    input  wire [3:0]  m_axi_bid,

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

    // Fixed AXI parameters
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = 3'b010;
    assign m_axi_arburst = 2'b01;
    assign m_axi_awlen   = 8'd0;
    assign m_axi_awsize  = 3'b010;
    assign m_axi_awburst = 2'b01;
    assign m_axi_wlast   = 1'b1;
    assign m_axi_rready  = 1'b1;

    // AXI ID for data bus master (M1)
    assign m_axi_arid = 4'b0100;
    assign m_axi_awid = 4'b0100;

    // FSM states
    localparam [2:0] IDLE    = 3'd0,
                     AR_WAIT = 3'd1,
                     R_WAIT  = 3'd2,
                     AW_WAIT = 3'd3,
                     W_WAIT  = 3'd4,
                     B_WAIT  = 3'd5;

    reg [2:0]  state_r;
    reg        gnt_r;
    reg        rvalid_r;
    reg [31:0] rdata_r;
    reg        rerr_r;

    // AXI output registers
    reg        ar_valid_r;
    reg [31:0] ar_addr_r;
    reg        aw_valid_r;
    reg [31:0] aw_addr_r;
    reg        w_valid_r;
    reg [31:0] w_data_r;
    reg [3:0]  w_strb_r;
    reg        b_ready_r;

    assign data_gnt_o    = gnt_r;
    assign data_rvalid_o = rvalid_r;
    assign data_rdata_o  = rdata_r;
    assign data_err_o    = rerr_r;

    assign m_axi_arvalid = ar_valid_r;
    assign m_axi_araddr  = ar_addr_r;
    assign m_axi_awvalid = aw_valid_r;
    assign m_axi_awaddr  = aw_addr_r;
    assign m_axi_wvalid  = w_valid_r;
    assign m_axi_wdata   = w_data_r;
    assign m_axi_wstrb   = w_strb_r;
    assign m_axi_bready  = b_ready_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            state_r    <= IDLE;
            gnt_r      <= 1'b0;
            rvalid_r   <= 1'b0;
            rdata_r    <= 32'd0;
            rerr_r     <= 1'b0;
            ar_valid_r <= 1'b0;
            ar_addr_r  <= 32'd0;
            aw_valid_r <= 1'b0;
            aw_addr_r  <= 32'd0;
            w_valid_r  <= 1'b0;
            w_data_r   <= 32'd0;
            w_strb_r   <= 4'd0;
            b_ready_r  <= 1'b0;
        end else begin
            // Default pulse signals
            gnt_r    <= 1'b0;
            rvalid_r <= 1'b0;
            rerr_r   <= 1'b0;

            case (state_r)
                IDLE: begin
                    ar_valid_r <= 1'b0;
                    aw_valid_r <= 1'b0;
                    w_valid_r  <= 1'b0;
                    b_ready_r  <= 1'b0;
                    if (data_req_i) begin
                        if (!data_we_i) begin
                            // Load: issue AXI read
                            ar_valid_r <= 1'b1;
                            ar_addr_r  <= data_addr_i;
                            state_r    <= AR_WAIT;
                        end else begin
                            // Store: issue AXI write (AW + W simultaneously)
                            aw_valid_r <= 1'b1;
                            aw_addr_r  <= data_addr_i;
                            w_valid_r  <= 1'b1;
                            w_data_r   <= data_wdata_i;
                            w_strb_r   <= data_be_i;
                            state_r    <= AW_WAIT;
                        end
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

                AW_WAIT: begin
                    // Handle AW and W handshakes independently
                    if (m_axi_awready) begin
                        aw_valid_r <= 1'b0;
                    end
                    if (m_axi_wready) begin
                        w_valid_r <= 1'b0;
                    end
                    // Both channels done (either just now or previously)
                    if ((m_axi_awready || !aw_valid_r) && (m_axi_wready || !w_valid_r)) begin
                        gnt_r     <= 1'b1;
                        b_ready_r <= 1'b1;
                        state_r   <= B_WAIT;
                    end else if (m_axi_awready && !m_axi_wready) begin
                        state_r <= W_WAIT;
                    end
                end

                W_WAIT: begin
                    // AW already accepted, waiting for W
                    if (m_axi_wready) begin
                        w_valid_r <= 1'b0;
                        gnt_r     <= 1'b1;
                        b_ready_r <= 1'b1;
                        state_r   <= B_WAIT;
                    end
                end

                B_WAIT: begin
                    if (m_axi_bvalid) begin
                        rvalid_r  <= 1'b1;
                        rerr_r    <= (m_axi_bresp != 2'b00);
                        b_ready_r <= 1'b0;
                        state_r   <= IDLE;
                    end
                end

                default: begin
                    state_r <= IDLE;
                end
            endcase
        end
    end

endmodule
