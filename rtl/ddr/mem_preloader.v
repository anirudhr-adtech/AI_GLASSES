`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Module: mem_preloader
// Description: Hex file preloader wrapper. Uses $readmemh to initialize
//              mem_array regions. Simulation-only utility.
//============================================================================

module mem_preloader #(
    parameter MEM_SIZE_BYTES = 1048576,
    parameter HEX_FILE       = "init.hex",
    parameter BASE_ADDR      = 0
)(
    input  wire        clk,
    input  wire        preload_en,

    // Direct memory write interface
    output reg         wr_en,
    output reg  [31:0] wr_addr,
    output reg  [7:0]  wr_data_byte
);

    // Temporary byte storage for loading
    reg [7:0] file_data [0:MEM_SIZE_BYTES-1];

    reg        preload_done;
    reg [31:0] byte_idx;
    reg        loading;

    integer i;

    initial begin
        wr_en         = 1'b0;
        wr_addr       = 32'd0;
        wr_data_byte  = 8'd0;
        preload_done  = 1'b0;
        byte_idx      = 32'd0;
        loading       = 1'b0;
        for (i = 0; i < MEM_SIZE_BYTES; i = i + 1)
            file_data[i] = 8'h00;
    end

    // Load hex file on preload_en assertion
    always @(posedge clk) begin
        wr_en <= 1'b0;

        if (preload_en && !preload_done && !loading) begin
            $readmemh(HEX_FILE, file_data);
            loading  <= 1'b1;
            byte_idx <= 32'd0;
        end

        if (loading) begin
            if (byte_idx < MEM_SIZE_BYTES) begin
                wr_en        <= 1'b1;
                wr_addr      <= BASE_ADDR + byte_idx;
                wr_data_byte <= file_data[byte_idx];
                byte_idx     <= byte_idx + 32'd1;
            end else begin
                loading      <= 1'b0;
                preload_done <= 1'b1;
            end
        end
    end

endmodule
