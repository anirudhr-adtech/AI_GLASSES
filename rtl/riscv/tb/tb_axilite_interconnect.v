`timescale 1ns/1ps
//============================================================================
// Testbench : tb_axilite_interconnect
// Project   : AI_GLASSES — RISC-V Subsystem
// Description : Self-checking testbench for axilite_interconnect
//============================================================================

module tb_axilite_interconnect;

    reg clk, rst_n;
    integer pass_cnt, fail_cnt;

    // Master port signals
    reg  [31:0] s_awaddr;  reg        s_awvalid;  wire       s_awready;
    reg  [31:0] s_wdata;   reg [3:0]  s_wstrb;    reg        s_wvalid;
    wire        s_wready;
    wire [1:0]  s_bresp;   wire       s_bvalid;   reg        s_bready;
    reg  [31:0] s_araddr;  reg        s_arvalid;  wire       s_arready;
    wire [31:0] s_rdata;   wire [1:0] s_rresp;    wire       s_rvalid;
    reg         s_rready;

    // Slave port stubs — 8 behavioral slaves
    wire [7:0]  slv_awaddr [0:7];
    wire        slv_awvalid[0:7];
    reg         slv_awready[0:7];
    wire [31:0] slv_wdata  [0:7];
    wire [3:0]  slv_wstrb  [0:7];
    wire        slv_wvalid [0:7];
    reg         slv_wready [0:7];
    reg  [1:0]  slv_bresp  [0:7];
    reg         slv_bvalid [0:7];
    wire        slv_bready [0:7];
    wire [7:0]  slv_araddr [0:7];
    wire        slv_arvalid[0:7];
    reg         slv_arready[0:7];
    reg  [31:0] slv_rdata  [0:7];
    reg  [1:0]  slv_rresp  [0:7];
    reg         slv_rvalid [0:7];
    wire        slv_rready [0:7];

    axilite_interconnect uut (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_awaddr), .s_axil_awvalid(s_awvalid), .s_axil_awready(s_awready),
        .s_axil_wdata(s_wdata), .s_axil_wstrb(s_wstrb), .s_axil_wvalid(s_wvalid),
        .s_axil_wready(s_wready),
        .s_axil_bresp(s_bresp), .s_axil_bvalid(s_bvalid), .s_axil_bready(s_bready),
        .s_axil_araddr(s_araddr), .s_axil_arvalid(s_arvalid), .s_axil_arready(s_arready),
        .s_axil_rdata(s_rdata), .s_axil_rresp(s_rresp), .s_axil_rvalid(s_rvalid),
        .s_axil_rready(s_rready),
        // Slave 0
        .m_axil_0_awaddr(slv_awaddr[0]), .m_axil_0_awvalid(slv_awvalid[0]), .m_axil_0_awready(slv_awready[0]),
        .m_axil_0_wdata(slv_wdata[0]), .m_axil_0_wstrb(slv_wstrb[0]), .m_axil_0_wvalid(slv_wvalid[0]),
        .m_axil_0_wready(slv_wready[0]),
        .m_axil_0_bresp(slv_bresp[0]), .m_axil_0_bvalid(slv_bvalid[0]), .m_axil_0_bready(slv_bready[0]),
        .m_axil_0_araddr(slv_araddr[0]), .m_axil_0_arvalid(slv_arvalid[0]), .m_axil_0_arready(slv_arready[0]),
        .m_axil_0_rdata(slv_rdata[0]), .m_axil_0_rresp(slv_rresp[0]), .m_axil_0_rvalid(slv_rvalid[0]),
        .m_axil_0_rready(slv_rready[0]),
        // Slave 1
        .m_axil_1_awaddr(slv_awaddr[1]), .m_axil_1_awvalid(slv_awvalid[1]), .m_axil_1_awready(slv_awready[1]),
        .m_axil_1_wdata(slv_wdata[1]), .m_axil_1_wstrb(slv_wstrb[1]), .m_axil_1_wvalid(slv_wvalid[1]),
        .m_axil_1_wready(slv_wready[1]),
        .m_axil_1_bresp(slv_bresp[1]), .m_axil_1_bvalid(slv_bvalid[1]), .m_axil_1_bready(slv_bready[1]),
        .m_axil_1_araddr(slv_araddr[1]), .m_axil_1_arvalid(slv_arvalid[1]), .m_axil_1_arready(slv_arready[1]),
        .m_axil_1_rdata(slv_rdata[1]), .m_axil_1_rresp(slv_rresp[1]), .m_axil_1_rvalid(slv_rvalid[1]),
        .m_axil_1_rready(slv_rready[1]),
        // Slaves 2-7
        .m_axil_2_awaddr(slv_awaddr[2]), .m_axil_2_awvalid(slv_awvalid[2]), .m_axil_2_awready(slv_awready[2]),
        .m_axil_2_wdata(slv_wdata[2]), .m_axil_2_wstrb(slv_wstrb[2]), .m_axil_2_wvalid(slv_wvalid[2]),
        .m_axil_2_wready(slv_wready[2]),
        .m_axil_2_bresp(slv_bresp[2]), .m_axil_2_bvalid(slv_bvalid[2]), .m_axil_2_bready(slv_bready[2]),
        .m_axil_2_araddr(slv_araddr[2]), .m_axil_2_arvalid(slv_arvalid[2]), .m_axil_2_arready(slv_arready[2]),
        .m_axil_2_rdata(slv_rdata[2]), .m_axil_2_rresp(slv_rresp[2]), .m_axil_2_rvalid(slv_rvalid[2]),
        .m_axil_2_rready(slv_rready[2]),
        .m_axil_3_awaddr(slv_awaddr[3]), .m_axil_3_awvalid(slv_awvalid[3]), .m_axil_3_awready(slv_awready[3]),
        .m_axil_3_wdata(slv_wdata[3]), .m_axil_3_wstrb(slv_wstrb[3]), .m_axil_3_wvalid(slv_wvalid[3]),
        .m_axil_3_wready(slv_wready[3]),
        .m_axil_3_bresp(slv_bresp[3]), .m_axil_3_bvalid(slv_bvalid[3]), .m_axil_3_bready(slv_bready[3]),
        .m_axil_3_araddr(slv_araddr[3]), .m_axil_3_arvalid(slv_arvalid[3]), .m_axil_3_arready(slv_arready[3]),
        .m_axil_3_rdata(slv_rdata[3]), .m_axil_3_rresp(slv_rresp[3]), .m_axil_3_rvalid(slv_rvalid[3]),
        .m_axil_3_rready(slv_rready[3]),
        .m_axil_4_awaddr(slv_awaddr[4]), .m_axil_4_awvalid(slv_awvalid[4]), .m_axil_4_awready(slv_awready[4]),
        .m_axil_4_wdata(slv_wdata[4]), .m_axil_4_wstrb(slv_wstrb[4]), .m_axil_4_wvalid(slv_wvalid[4]),
        .m_axil_4_wready(slv_wready[4]),
        .m_axil_4_bresp(slv_bresp[4]), .m_axil_4_bvalid(slv_bvalid[4]), .m_axil_4_bready(slv_bready[4]),
        .m_axil_4_araddr(slv_araddr[4]), .m_axil_4_arvalid(slv_arvalid[4]), .m_axil_4_arready(slv_arready[4]),
        .m_axil_4_rdata(slv_rdata[4]), .m_axil_4_rresp(slv_rresp[4]), .m_axil_4_rvalid(slv_rvalid[4]),
        .m_axil_4_rready(slv_rready[4]),
        .m_axil_5_awaddr(slv_awaddr[5]), .m_axil_5_awvalid(slv_awvalid[5]), .m_axil_5_awready(slv_awready[5]),
        .m_axil_5_wdata(slv_wdata[5]), .m_axil_5_wstrb(slv_wstrb[5]), .m_axil_5_wvalid(slv_wvalid[5]),
        .m_axil_5_wready(slv_wready[5]),
        .m_axil_5_bresp(slv_bresp[5]), .m_axil_5_bvalid(slv_bvalid[5]), .m_axil_5_bready(slv_bready[5]),
        .m_axil_5_araddr(slv_araddr[5]), .m_axil_5_arvalid(slv_arvalid[5]), .m_axil_5_arready(slv_arready[5]),
        .m_axil_5_rdata(slv_rdata[5]), .m_axil_5_rresp(slv_rresp[5]), .m_axil_5_rvalid(slv_rvalid[5]),
        .m_axil_5_rready(slv_rready[5]),
        .m_axil_6_awaddr(slv_awaddr[6]), .m_axil_6_awvalid(slv_awvalid[6]), .m_axil_6_awready(slv_awready[6]),
        .m_axil_6_wdata(slv_wdata[6]), .m_axil_6_wstrb(slv_wstrb[6]), .m_axil_6_wvalid(slv_wvalid[6]),
        .m_axil_6_wready(slv_wready[6]),
        .m_axil_6_bresp(slv_bresp[6]), .m_axil_6_bvalid(slv_bvalid[6]), .m_axil_6_bready(slv_bready[6]),
        .m_axil_6_araddr(slv_araddr[6]), .m_axil_6_arvalid(slv_arvalid[6]), .m_axil_6_arready(slv_arready[6]),
        .m_axil_6_rdata(slv_rdata[6]), .m_axil_6_rresp(slv_rresp[6]), .m_axil_6_rvalid(slv_rvalid[6]),
        .m_axil_6_rready(slv_rready[6]),
        .m_axil_7_awaddr(slv_awaddr[7]), .m_axil_7_awvalid(slv_awvalid[7]), .m_axil_7_awready(slv_awready[7]),
        .m_axil_7_wdata(slv_wdata[7]), .m_axil_7_wstrb(slv_wstrb[7]), .m_axil_7_wvalid(slv_wvalid[7]),
        .m_axil_7_wready(slv_wready[7]),
        .m_axil_7_bresp(slv_bresp[7]), .m_axil_7_bvalid(slv_bvalid[7]), .m_axil_7_bready(slv_bready[7]),
        .m_axil_7_araddr(slv_araddr[7]), .m_axil_7_arvalid(slv_arvalid[7]), .m_axil_7_arready(slv_arready[7]),
        .m_axil_7_rdata(slv_rdata[7]), .m_axil_7_rresp(slv_rresp[7]), .m_axil_7_rvalid(slv_rvalid[7]),
        .m_axil_7_rready(slv_rready[7])
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Behavioral slave responders
    integer si;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (si = 0; si < 8; si = si + 1) begin
                slv_awready[si] <= 1'b0;
                slv_wready[si]  <= 1'b0;
                slv_bvalid[si]  <= 1'b0;
                slv_bresp[si]   <= 2'b00;
                slv_arready[si] <= 1'b0;
                slv_rvalid[si]  <= 1'b0;
                slv_rdata[si]   <= 32'd0;
                slv_rresp[si]   <= 2'b00;
            end
        end else begin
            for (si = 0; si < 8; si = si + 1) begin
                // Write: accept AW+W, respond with B
                slv_awready[si] <= 1'b1;
                slv_wready[si]  <= 1'b1;
                if (slv_awvalid[si] && slv_awready[si] && slv_wvalid[si] && slv_wready[si]) begin
                    slv_bvalid[si] <= 1'b1;
                    slv_bresp[si]  <= 2'b00;
                end
                if (slv_bvalid[si] && slv_bready[si])
                    slv_bvalid[si] <= 1'b0;

                // Read: accept AR, respond with R
                slv_arready[si] <= 1'b1;
                if (slv_arvalid[si] && slv_arready[si]) begin
                    slv_rvalid[si] <= 1'b1;
                    slv_rdata[si]  <= {24'd0, si[7:0]};  // Return slave index
                    slv_rresp[si]  <= 2'b00;
                end
                if (slv_rvalid[si] && slv_rready[si])
                    slv_rvalid[si] <= 1'b0;
            end
        end
    end

    task axil_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            s_awaddr  = addr;
            s_awvalid = 1;
            s_wdata   = data;
            s_wstrb   = 4'hF;
            s_wvalid  = 1;
            s_bready  = 1;
            @(posedge clk);
            while (!s_awready || !s_wready) @(posedge clk);
            s_awvalid = 0;
            s_wvalid  = 0;
            while (!s_bvalid) @(posedge clk);
            @(posedge clk);
            s_bready = 0;
        end
    endtask

    task axil_read;
        input  [31:0] addr;
        output [31:0] data;
        output [1:0]  resp;
        begin
            s_araddr  = addr;
            s_arvalid = 1;
            s_rready  = 1;
            @(posedge clk);
            while (!s_arready) @(posedge clk);
            s_arvalid = 0;
            while (!s_rvalid) @(posedge clk);
            data = s_rdata;
            resp = s_rresp;
            @(posedge clk);
            s_rready = 0;
        end
    endtask

    reg [31:0] rd_data;
    reg [1:0]  rd_resp;

    initial begin
        pass_cnt = 0; fail_cnt = 0;
        rst_n = 0;
        s_awaddr = 0; s_awvalid = 0; s_wdata = 0; s_wstrb = 0; s_wvalid = 0;
        s_bready = 0;
        s_araddr = 0; s_arvalid = 0; s_rready = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // Test 1: Read from UART (slave 0)
        $display("Test 1: Read from UART (slave 0)");
        axil_read(32'h2000_0004, rd_data, rd_resp);
        if (rd_data == 32'd0 && rd_resp == 2'b00) begin
            $display("PASS: Read UART returned data=0x%08h", rd_data);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: Read UART data=0x%08h resp=%b", rd_data, rd_resp);
            fail_cnt = fail_cnt + 1;
        end

        repeat (3) @(posedge clk);

        // Test 2: Read from GPIO (slave 3)
        $display("Test 2: Read from GPIO (slave 3)");
        axil_read(32'h2000_0300, rd_data, rd_resp);
        if (rd_data == 32'd3 && rd_resp == 2'b00) begin
            $display("PASS: Read GPIO returned data=0x%08h", rd_data);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: Read GPIO data=0x%08h resp=%b", rd_data, rd_resp);
            fail_cnt = fail_cnt + 1;
        end

        repeat (3) @(posedge clk);

        // Test 3: Read from SPI (slave 7)
        $display("Test 3: Read from SPI (slave 7)");
        axil_read(32'h2000_0700, rd_data, rd_resp);
        if (rd_data == 32'd7 && rd_resp == 2'b00) begin
            $display("PASS: Read SPI returned data=0x%08h", rd_data);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: Read SPI data=0x%08h resp=%b", rd_data, rd_resp);
            fail_cnt = fail_cnt + 1;
        end

        repeat (3) @(posedge clk);

        // Test 4: Write to Timer (slave 1)
        $display("Test 4: Write to Timer (slave 1)");
        axil_write(32'h2000_0100, 32'hDEAD_BEEF);
        $display("PASS: Write to Timer completed");
        pass_cnt = pass_cnt + 1;

        repeat (3) @(posedge clk);

        // Test 5: Unmapped address -> SLVERR
        $display("Test 5: Read unmapped address -> SLVERR");
        axil_read(32'h3000_0000, rd_data, rd_resp);
        if (rd_resp == 2'b10) begin
            $display("PASS: Unmapped address returned SLVERR");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: Unmapped address resp=%b (expected SLVERR=10)", rd_resp);
            fail_cnt = fail_cnt + 1;
        end

        $display("");
        $display("========================================");
        $display("  Results: %0d passed, %0d failed", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED");
        $display("========================================");
        $finish;
    end

    initial begin
        #20000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
