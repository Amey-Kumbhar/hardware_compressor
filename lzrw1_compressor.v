`timescale 1ns / 1ps

module lzrw1_compressor #(
    parameter ADDR_WIDTH = 24,      // Upgraded: 24-bit pointers = 16 Megabyte max file size
    parameter HASH_WIDTH = 12       // 4096 Hash table entries (Standard LZRW1)
)(
    input wire clk,            // Mandated clock naming
    input wire rst,
    
    input wire start,
    input wire [7:0] data_in,
    input wire data_in_valid,
    input wire eof,                 
    
    output reg [7:0] out_literal,
    output reg [11:0] out_match_offset, 
    output reg [3:0] out_match_len,
    output reg out_is_match,        
    output reg out_valid,
    output reg done
);

    
    reg [7:0] in_buffer [0:(1<<ADDR_WIDTH)-1];
    
    // Hash table now stores 24-bit absolute pointers
    reg [ADDR_WIDTH-1:0] hash_table [0:(1<<HASH_WIDTH)-1];

    reg [ADDR_WIDTH-1:0] write_ptr;
    reg [ADDR_WIDTH-1:0] read_ptr;
    reg [ADDR_WIDTH-1:0] file_size;
    
    reg [HASH_WIDTH-1:0] current_hash;
    reg [ADDR_WIDTH-1:0] match_ptr;
    reg [3:0] match_len; 
    
    wire [7:0] b1 = in_buffer[read_ptr];
    wire [7:0] b2 = in_buffer[read_ptr+1];
    wire [7:0] b3 = in_buffer[read_ptr+2];

    wire [HASH_WIDTH-1:0] calc_hash = ((b1 << 4) ^ (b2 << 2) ^ b3) & 12'hFFF;

    localparam IDLE       = 3'd0,
               LOAD       = 3'd1,
               HASH       = 3'd2,
               CHECK      = 3'd3,
               EXTEND     = 3'd4, 
               EMIT_LIT   = 3'd5,
               EMIT_MATCH = 3'd6,
               FINISH     = 3'd7;

    reg [2:0] state;
    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            write_ptr <= 0;
            read_ptr <= 0;
            file_size <= 0;
            out_valid <= 0;
            done <= 0;
            match_len <= 0;
            for (i = 0; i < (1<<HASH_WIDTH); i = i + 1) begin
                hash_table[i] <= 0;
            end
        end else begin
            out_valid <= 0;
            done <= 0;

            case (state)
                IDLE: begin
                    write_ptr <= 0;
                    read_ptr <= 0;
                    if (start) state <= LOAD;
                end

                LOAD: begin
                    if (data_in_valid) begin
                        in_buffer[write_ptr] <= data_in;
                        write_ptr <= write_ptr + 1;
                    end
                    if (eof) begin
                        file_size <= write_ptr;
                        state <= HASH;
                    end
                end

                HASH: begin
                    if (read_ptr >= file_size - 2) begin
                        state <= EMIT_LIT;
                    end else begin
                        current_hash <= calc_hash;
                        match_ptr <= hash_table[calc_hash]; 
                        match_len <= 3; 
                        state <= CHECK;
                    end
                end

                CHECK: begin
                    hash_table[current_hash] <= read_ptr;
                    
                    // Hardware specifically ensures the match is within the 4096-byte window limit
                    if (match_ptr != 0 && match_ptr < read_ptr && 
                        (read_ptr - match_ptr) <= 12'hFFF && 
                        in_buffer[match_ptr] == b1 && 
                        in_buffer[match_ptr+1] == b2 && 
                        in_buffer[match_ptr+2] == b3) begin
                        state <= EXTEND;
                    end else begin
                        state <= EMIT_LIT;
                    end
                end

                EXTEND: begin
                    if (match_len < 15 && (read_ptr + match_len) < file_size &&
                        in_buffer[match_ptr + match_len] == in_buffer[read_ptr + match_len]) begin
                        match_len <= match_len + 1; 
                    end else begin
                        state <= EMIT_MATCH; 
                    end
                end

                EMIT_LIT: begin
                    if (read_ptr >= file_size) begin
                        state <= FINISH;
                    end else begin
                        out_literal <= in_buffer[read_ptr];
                        out_is_match <= 0;
                        out_valid <= 1;
                        read_ptr <= read_ptr + 1;
                        state <= HASH;
                    end
                end

                EMIT_MATCH: begin
                    out_match_offset <= read_ptr - match_ptr;
                    out_match_len <= match_len; 
                    out_is_match <= 1;
                    out_valid <= 1;
                    read_ptr <= read_ptr + match_len; 
                    state <= HASH;
                end

                FINISH: begin
                    done <= 1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule
