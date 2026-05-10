module game_over_overlay (
    input  logic        clk,
    input  logic [9:0]  DrawX,
    input  logic [9:0]  DrawY,
    input  logic [3:0]  p1_hp,
    input  logic [3:0]  p2_hp,
    input  logic [7:0]  kill_count,

    output logic        active,
    output logic [3:0]  Red,
    output logic [3:0]  Green,
    output logic [3:0]  Blue
);

    localparam logic [9:0] TEXT_X = 10'd176;
    localparam logic [9:0] TEXT_Y = 10'd140;
    localparam logic [9:0] TEXT_W = 10'd288;
    localparam logic [9:0] TEXT_H = 10'd80;

    //draw the dynamic score as xx/100 under the YOU DIED image
    localparam logic [9:0] COUNT_X = TEXT_X + 10'd88;
    localparam logic [9:0] COUNT_Y = TEXT_Y + 10'd90;
    localparam logic [9:0] COUNT_W = 10'd112;
    localparam logic [9:0] COUNT_H = 10'd16;

    logic game_over;
    logic text_area;
    logic count_area;

    logic [14:0] text_addr;
    logic [3:0]  text_idx;
    logic [3:0]  text_r, text_g, text_b;

    logic [7:0] kill_clamped;
    logic [7:0] remainder_after_tens;
    logic [3:0] count_tens, count_ones;

    logic [9:0] count_rel_x, count_rel_y;
    logic [2:0] count_char_index;
    logic [3:0] count_local_x, count_local_y;
    logic [3:0] count_digit;
    logic       count_digit_visible;
    logic       count_slash_visible;
    logic       count_pixel;

    assign game_over = (p1_hp == 4'd0) && (p2_hp == 4'd0);
    assign active = game_over;

    assign text_area = game_over &&
                       DrawX >= TEXT_X && DrawX < TEXT_X + TEXT_W &&
                       DrawY >= TEXT_Y && DrawY < TEXT_Y + TEXT_H;

    assign count_area = game_over &&
                        DrawX >= COUNT_X && DrawX < COUNT_X + COUNT_W &&
                        DrawY >= COUNT_Y && DrawY < COUNT_Y + COUNT_H;

    always_comb begin
        if (text_area)
            text_addr = (DrawY - TEXT_Y) * 15'd288 + (DrawX - TEXT_X);
        else
            text_addr = 15'd0;
    end

    Text_rom text_rom_inst (
        .clka(clk),
        .ena(1'b1),
        .addra(text_addr),
        .douta(text_idx)
    );

    Text_palette text_palette_inst (
        .index(text_idx),
        .red(text_r),
        .green(text_g),
        .blue(text_b)
    );

    always_comb begin
        kill_clamped = (kill_count > 8'd100) ? 8'd100 : kill_count;

        if (kill_clamped >= 8'd100) begin
            count_tens = 4'd0;
            remainder_after_tens = 8'd0;
        end else if (kill_clamped >= 8'd90) begin
            count_tens = 4'd9;
            remainder_after_tens = kill_clamped - 8'd90;
        end else if (kill_clamped >= 8'd80) begin
            count_tens = 4'd8;
            remainder_after_tens = kill_clamped - 8'd80;
        end else if (kill_clamped >= 8'd70) begin
            count_tens = 4'd7;
            remainder_after_tens = kill_clamped - 8'd70;
        end else if (kill_clamped >= 8'd60) begin
            count_tens = 4'd6;
            remainder_after_tens = kill_clamped - 8'd60;
        end else if (kill_clamped >= 8'd50) begin
            count_tens = 4'd5;
            remainder_after_tens = kill_clamped - 8'd50;
        end else if (kill_clamped >= 8'd40) begin
            count_tens = 4'd4;
            remainder_after_tens = kill_clamped - 8'd40;
        end else if (kill_clamped >= 8'd30) begin
            count_tens = 4'd3;
            remainder_after_tens = kill_clamped - 8'd30;
        end else if (kill_clamped >= 8'd20) begin
            count_tens = 4'd2;
            remainder_after_tens = kill_clamped - 8'd20;
        end else if (kill_clamped >= 8'd10) begin
            count_tens = 4'd1;
            remainder_after_tens = kill_clamped - 8'd10;
        end else begin
            count_tens = 4'd0;
            remainder_after_tens = kill_clamped;
        end

        count_ones = remainder_after_tens[3:0];
    end

    assign count_rel_x = DrawX - COUNT_X;
    assign count_rel_y = DrawY - COUNT_Y;
    assign count_char_index = count_rel_x[6:4];
    assign count_local_x = count_rel_x[3:0];
    assign count_local_y = count_rel_y[3:0];

    always_comb begin
        count_digit = 4'd0;
        count_digit_visible = 1'b0;
        count_slash_visible = 1'b0;

        if (kill_clamped >= 8'd100) begin
            case (count_char_index)
                3'd0: begin count_digit = 4'd1; count_digit_visible = 1'b1; end
                3'd1: begin count_digit = 4'd0; count_digit_visible = 1'b1; end
                3'd2: begin count_digit = 4'd0; count_digit_visible = 1'b1; end
                3'd3: begin count_slash_visible = 1'b1; end
                3'd4: begin count_digit = 4'd1; count_digit_visible = 1'b1; end
                3'd5: begin count_digit = 4'd0; count_digit_visible = 1'b1; end
                3'd6: begin count_digit = 4'd0; count_digit_visible = 1'b1; end
                default: count_digit_visible = 1'b0;
            endcase
        end else begin
            case (count_char_index)
                3'd0: begin count_digit = count_tens; count_digit_visible = 1'b1; end
                3'd1: begin count_digit = count_ones; count_digit_visible = 1'b1; end
                3'd2: begin count_slash_visible = 1'b1; end
                3'd3: begin count_digit = 4'd1; count_digit_visible = 1'b1; end
                3'd4: begin count_digit = 4'd0; count_digit_visible = 1'b1; end
                3'd5: begin count_digit = 4'd0; count_digit_visible = 1'b1; end
                default: count_digit_visible = 1'b0;
            endcase
        end
    end

    function automatic logic [4:0] digit_row(input logic [3:0] digit, input logic [2:0] row);
        begin
            digit_row = 5'b00000;
            case (digit)
                4'd0: case (row)
                    3'd0: digit_row = 5'b01110;
                    3'd1: digit_row = 5'b10001;
                    3'd2: digit_row = 5'b10011;
                    3'd3: digit_row = 5'b10101;
                    3'd4: digit_row = 5'b11001;
                    3'd5: digit_row = 5'b10001;
                    3'd6: digit_row = 5'b01110;
                endcase
                4'd1: case (row)
                    3'd0: digit_row = 5'b00100;
                    3'd1: digit_row = 5'b01100;
                    3'd2: digit_row = 5'b00100;
                    3'd3: digit_row = 5'b00100;
                    3'd4: digit_row = 5'b00100;
                    3'd5: digit_row = 5'b00100;
                    3'd6: digit_row = 5'b01110;
                endcase
                4'd2: case (row)
                    3'd0: digit_row = 5'b01110;
                    3'd1: digit_row = 5'b10001;
                    3'd2: digit_row = 5'b00001;
                    3'd3: digit_row = 5'b00010;
                    3'd4: digit_row = 5'b00100;
                    3'd5: digit_row = 5'b01000;
                    3'd6: digit_row = 5'b11111;
                endcase
                4'd3: case (row)
                    3'd0: digit_row = 5'b11110;
                    3'd1: digit_row = 5'b00001;
                    3'd2: digit_row = 5'b00001;
                    3'd3: digit_row = 5'b01110;
                    3'd4: digit_row = 5'b00001;
                    3'd5: digit_row = 5'b00001;
                    3'd6: digit_row = 5'b11110;
                endcase
                4'd4: case (row)
                    3'd0: digit_row = 5'b00010;
                    3'd1: digit_row = 5'b00110;
                    3'd2: digit_row = 5'b01010;
                    3'd3: digit_row = 5'b10010;
                    3'd4: digit_row = 5'b11111;
                    3'd5: digit_row = 5'b00010;
                    3'd6: digit_row = 5'b00010;
                endcase
                4'd5: case (row)
                    3'd0: digit_row = 5'b11111;
                    3'd1: digit_row = 5'b10000;
                    3'd2: digit_row = 5'b10000;
                    3'd3: digit_row = 5'b11110;
                    3'd4: digit_row = 5'b00001;
                    3'd5: digit_row = 5'b00001;
                    3'd6: digit_row = 5'b11110;
                endcase
                4'd6: case (row)
                    3'd0: digit_row = 5'b00110;
                    3'd1: digit_row = 5'b01000;
                    3'd2: digit_row = 5'b10000;
                    3'd3: digit_row = 5'b11110;
                    3'd4: digit_row = 5'b10001;
                    3'd5: digit_row = 5'b10001;
                    3'd6: digit_row = 5'b01110;
                endcase
                4'd7: case (row)
                    3'd0: digit_row = 5'b11111;
                    3'd1: digit_row = 5'b00001;
                    3'd2: digit_row = 5'b00010;
                    3'd3: digit_row = 5'b00100;
                    3'd4: digit_row = 5'b01000;
                    3'd5: digit_row = 5'b01000;
                    3'd6: digit_row = 5'b01000;
                endcase
                4'd8: case (row)
                    3'd0: digit_row = 5'b01110;
                    3'd1: digit_row = 5'b10001;
                    3'd2: digit_row = 5'b10001;
                    3'd3: digit_row = 5'b01110;
                    3'd4: digit_row = 5'b10001;
                    3'd5: digit_row = 5'b10001;
                    3'd6: digit_row = 5'b01110;
                endcase
                4'd9: case (row)
                    3'd0: digit_row = 5'b01110;
                    3'd1: digit_row = 5'b10001;
                    3'd2: digit_row = 5'b10001;
                    3'd3: digit_row = 5'b01111;
                    3'd4: digit_row = 5'b00001;
                    3'd5: digit_row = 5'b00010;
                    3'd6: digit_row = 5'b11100;
                endcase
                default: digit_row = 5'b00000;
            endcase
        end
    endfunction

    function automatic logic digit_pixel(input logic [3:0] digit, input logic [3:0] x, input logic [3:0] y);
        logic [4:0] row_bits;
        logic [2:0] row;
        logic [2:0] col;
        begin
            digit_pixel = 1'b0;
            row_bits = 5'b00000;
            row = 3'd0;
            col = 3'd0;
            if (x >= 4'd3 && x < 4'd13 && y >= 4'd1 && y < 4'd15) begin
                row = (y - 4'd1) >> 1;
                col = (x - 4'd3) >> 1;
                row_bits = digit_row(digit, row);
                digit_pixel = row_bits[3'd4 - col];
            end
        end
    endfunction

    function automatic logic slash_pixel(input logic [3:0] x, input logic [3:0] y);
        logic [3:0] y_half;
        begin
            slash_pixel = 1'b0;
            y_half = 4'd0;
            if (y >= 4'd1 && y < 4'd15) begin
                y_half = y >> 1;
                slash_pixel = (x == (4'd11 - y_half)) || (x == (4'd12 - y_half));
            end
        end
    endfunction

    assign count_pixel = count_area &&
                         ((count_digit_visible && digit_pixel(count_digit, count_local_x, count_local_y)) ||
                          (count_slash_visible && slash_pixel(count_local_x, count_local_y)));

    always_comb begin
        Red = 4'h0;
        Green = 4'h0;
        Blue = 4'h0;

        if (game_over) begin
            Red = 4'h1;
            Green = 4'h0;
            Blue = 4'h0;

            if (text_area && text_idx != 4'h0) begin
                Red = text_r;
                Green = text_g;
                Blue = text_b;
            end

            if (count_pixel) begin
                Red = 4'hF;
                Green = 4'hF;
                Blue = 4'hF;
            end
        end
    end

endmodule
