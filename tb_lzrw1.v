`timescale 1ns / 1ps

module tb_lzrw1();

    reg clk;
    reg rst;
    reg start;
    reg [7:0] data_in;
    reg data_in_valid;
    reg eof;

    wire [7:0] out_literal;
    wire [11:0] out_match_offset;
    wire [3:0] out_match_len;
    wire out_is_match;
    wire out_valid;
    wire done;

    integer in_file_id, out_file_id, char_in;

    reg [15:0] control_word;
    reg [7:0]  item_buffer [0:47]; 
    integer    item_count;
    integer    byte_count;
    integer    i;

    // Instantiate UUT (It inherits the new 24-bit 16MB default parameter)
    lzrw1_compressor uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .data_in(data_in),
        .data_in_valid(data_in_valid),
        .eof(eof),
        .out_literal(out_literal),
        .out_match_offset(out_match_offset),
        .out_match_len(out_match_len),
        .out_is_match(out_is_match),
        .out_valid(out_valid),
        .done(done)
    );

    // 100MHz clock (10ns period) 
    always #5 clk = ~clk;

    initial begin
        clk = 0; rst = 1; start = 0; 
        data_in = 0; data_in_valid = 0; eof = 0;
        control_word = 0; item_count = 0; byte_count = 0;

        in_file_id = $fopen("D:/Modelsim/input_txt.txt", "r");
        out_file_id = $fopen("compressed_out.bin", "wb"); 

        if (in_file_id == 0 || out_file_id == 0) begin
            $display("ERROR: File I/O failure.");
            $finish;
        end

        #20 rst = 0; 
        #10 start = 1;
        #10 start = 0;

        $display("Starting compression... This may take a moment for large files.");

        // Reads ANY file size until the absolute end
        while (!$feof(in_file_id)) begin
            char_in = $fgetc(in_file_id);
            if (char_in != -1) begin
                data_in = char_in[7:0]; 
                data_in_valid = 1;
                #10; 
            end
        end
        
        data_in_valid = 0;
        eof = 1;
        #10 eof = 0;

        wait (done == 1'b1);
        
        // Flush remaining buffer on EOF
        if (item_count > 0) begin
            $fwrite(out_file_id, "%c%c", control_word[7:0], control_word[15:8]);
            for(i = 0; i < byte_count; i = i + 1) begin
                $fwrite(out_file_id, "%c", item_buffer[i]);
            end
        end

        #50;
        $fclose(in_file_id);
        $fclose(out_file_id);
        
        $display("Done. Binary output written to 'compressed_out.bin'.");
        $finish;
    end

    // Monitor Output and Group into LZRW1 Binary Blocks
    always @(posedge clk) begin
        if (out_valid) begin
            if (out_is_match) begin
                control_word[item_count] = 1'b1;
                item_buffer[byte_count]   = {out_match_len[3:0], out_match_offset[11:8]};
                item_buffer[byte_count+1] = out_match_offset[7:0];
                byte_count = byte_count + 2;
            end else begin
                control_word[item_count] = 1'b0;
                item_buffer[byte_count] = out_literal;
                byte_count = byte_count + 1;
            end
            
            item_count = item_count + 1;

            if (item_count == 16) begin
                $fwrite(out_file_id, "%c%c", control_word[7:0], control_word[15:8]);
                for(i = 0; i < byte_count; i = i + 1) begin
                    $fwrite(out_file_id, "%c", item_buffer[i]);
                end
                
                item_count = 0;
                byte_count = 0;
                control_word = 0;
            end
        end
    end
endmodule
