`timescale 1ns / 1ps

module lzrw1_decompressor #(
    parameter ADDR_WIDTH = 24 // 24-bit pointers = 16 Megabyte max file size
)(
    input wire clk,
    input wire rst,
    input wire start,
    input wire [7:0] data_in,
    input wire data_in_valid,
    input wire eof,

    output reg [7:0] data_out,
    output reg out_valid,
    output reg done
);

    // Memory Buffers
    // comp_buffer holds the incoming .bin file
    // hist_buffer holds the decompressed data so we can look back for matches
    reg [7:0] comp_buffer [0:(1<<ADDR_WIDTH)-1];
    reg [7:0] hist_buffer [0:(1<<ADDR_WIDTH)-1];

    reg [ADDR_WIDTH-1:0] read_ptr;
    reg [ADDR_WIDTH-1:0] write_ptr;
    reg [ADDR_WIDTH-1:0] file_size;

    reg [15:0] control_word;
    reg [4:0]  item_count;
    reg [11:0] match_offset;
    reg [3:0]  match_len;
    reg [3:0]  copy_count;

    // FSM States
    localparam IDLE         = 4'd0,
               LOAD         = 4'd1,
               FETCH_CTRL_L = 4'd2,
               FETCH_CTRL_H = 4'd3,
               CHECK_ITEM   = 4'd4,
               FETCH_LIT    = 4'd5,
               FETCH_MATCH_0= 4'd6,
               FETCH_MATCH_1= 4'd7,
               DO_COPY      = 4'd8,
               FINISH       = 4'd9;

    reg [3:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            read_ptr <= 0;
            write_ptr <= 0;
            file_size <= 0;
            out_valid <= 0;
            done <= 0;
        end else begin
            out_valid <= 0; // Default to 0 unless we explicitly output a byte

            case (state)
                IDLE: begin
                    read_ptr <= 0;
                    write_ptr <= 0;
                    if (start) state <= LOAD;
                end

                // Step 1: Load the entire compressed file into memory
                LOAD: begin
                    if (data_in_valid) begin
                        comp_buffer[write_ptr] <= data_in;
                        write_ptr <= write_ptr + 1;
                    end
                    if (eof) begin
                        file_size <= write_ptr; // Save total size
                        write_ptr <= 0; // Reset write pointer for output history
                        read_ptr <= 0;  // Reset read pointer to start decoding
                        state <= FETCH_CTRL_L;
                    end
                end

                // Step 2: Grab the lower 8 bits of the Control Word
                FETCH_CTRL_L: begin
                    if (read_ptr >= file_size) begin
                        state <= FINISH;
                    end else begin
                        control_word[7:0] <= comp_buffer[read_ptr];
                        read_ptr <= read_ptr + 1;
                        state <= FETCH_CTRL_H;
                    end
                end

                // Step 3: Grab the upper 8 bits of the Control Word
                FETCH_CTRL_H: begin
                    control_word[15:8] <= comp_buffer[read_ptr];
                    read_ptr <= read_ptr + 1;
                    item_count <= 0;
                    state <= CHECK_ITEM;
                end

                // Step 4: Check the current item's control bit
                CHECK_ITEM: begin
                    // If we've processed 16 items, we need a new control word
                    if (read_ptr >= file_size) begin
                        state <= FINISH; 
                    end else if (item_count == 16) begin
                        state <= FETCH_CTRL_L;
                    end else begin
                        if (control_word[item_count] == 1'b0) begin
                            state <= FETCH_LIT;     // Bit is 0: Literal Character
                        end else begin
                            state <= FETCH_MATCH_0; // Bit is 1: Compressed Match
                        end
                    end
                end

                // Step 5A: Handle a Literal Character
                FETCH_LIT: begin
                    if (read_ptr < file_size) begin
                        // Save to history and output it simultaneously
                        hist_buffer[write_ptr] <= comp_buffer[read_ptr];
                        data_out <= comp_buffer[read_ptr];
                        out_valid <= 1;
                        
                        write_ptr <= write_ptr + 1;
                        read_ptr <= read_ptr + 1;
                    end
                    item_count <= item_count + 1;
                    state <= CHECK_ITEM;
                end

                // Step 5B: Handle a Compressed Match (Read Length & Top Offset)
                FETCH_MATCH_0: begin
                    if (read_ptr < file_size) begin
                        match_len <= comp_buffer[read_ptr][7:4];
                        match_offset[11:8] <= comp_buffer[read_ptr][3:0];
                        read_ptr <= read_ptr + 1;
                        state <= FETCH_MATCH_1;
                    end else state <= FINISH;
                end

                // Step 5C: Handle a Compressed Match (Read Bottom Offset)
                FETCH_MATCH_1: begin
                     if (read_ptr < file_size) begin
                        match_offset[7:0] <= comp_buffer[read_ptr];
                        read_ptr <= read_ptr + 1;
                        copy_count <= 0;
                        state <= DO_COPY;
                     end else state <= FINISH;
                end

                // Step 5D: Perform the look-back copy operation
                DO_COPY: begin
                    // Look back in our history buffer and copy the character
                    hist_buffer[write_ptr] <= hist_buffer[write_ptr - match_offset];
                    data_out <= hist_buffer[write_ptr - match_offset];
                    out_valid <= 1;
                    write_ptr <= write_ptr + 1;
                    
                    if (copy_count == match_len - 1) begin
                        item_count <= item_count + 1;
                        state <= CHECK_ITEM; // Done copying, check next item
                    end else begin
                        copy_count <= copy_count + 1; // Keep looping
                    end
                end

                FINISH: begin
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
