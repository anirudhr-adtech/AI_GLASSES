`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Testbench: tb_line_buffer
//////////////////////////////////////////////////////////////////////////////

module tb_line_buffer;

    reg        clk;
    reg        rst_n;
    reg        wr_en;
    reg        wr_line_sel;
    reg [9:0]  wr_addr;
    reg [23:0] wr_data;
    reg        rd_line_sel;
    reg [9:0]  rd_addr;
    wire [23:0] rd_data;

    integer err_count;
    integer i;

    line_buffer #(.MAX_WIDTH(16)) uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .wr_en       (wr_en),
        .wr_line_sel (wr_line_sel),
        .wr_addr     (wr_addr),
        .wr_data     (wr_data),
        .rd_line_sel (rd_line_sel),
        .rd_addr     (rd_addr),
        .rd_data     (rd_data)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        err_count   = 0;
        rst_n       = 0;
        wr_en       = 0;
        wr_line_sel = 0;
        wr_addr     = 0;
        wr_data     = 0;
        rd_line_sel = 0;
        rd_addr     = 0;

        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Write 8 pixels to line A
        wr_line_sel = 0;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            wr_en   = 1;
            wr_addr = i;
            wr_data = {8'd100 + i, 8'd150 + i, 8'd200 + i};  // RGB
        end
        @(posedge clk);
        wr_en = 0;

        // Write 8 pixels to line B
        wr_line_sel = 1;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            wr_en   = 1;
            wr_addr = i;
            wr_data = {8'd10 + i, 8'd20 + i, 8'd30 + i};
        end
        @(posedge clk);
        wr_en = 0;

        // Read back line A and verify
        rd_line_sel = 0;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            rd_addr = i;
            @(posedge clk);  // 1 cycle read latency
            #1;
            if (rd_data !== {8'd100 + i[7:0], 8'd150 + i[7:0], 8'd200 + i[7:0]}) begin
                $display("FAIL: Line A[%0d] = %h, expected %h",
                         i, rd_data, {8'd100 + i[7:0], 8'd150 + i[7:0], 8'd200 + i[7:0]});
                err_count = err_count + 1;
            end
        end

        // Read back line B and verify
        rd_line_sel = 1;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            rd_addr = i;
            @(posedge clk);
            #1;
            if (rd_data !== {8'd10 + i[7:0], 8'd20 + i[7:0], 8'd30 + i[7:0]}) begin
                $display("FAIL: Line B[%0d] = %h, expected %h",
                         i, rd_data, {8'd10 + i[7:0], 8'd20 + i[7:0], 8'd30 + i[7:0]});
                err_count = err_count + 1;
            end
        end

        // Summary
        if (err_count == 0)
            $display("PASS: tb_line_buffer — all tests passed");
        else
            $display("FAIL: tb_line_buffer — %0d errors", err_count);

        $finish;
    end

endmodule
