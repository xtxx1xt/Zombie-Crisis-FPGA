module color_mapper (
    input  logic        clk,
    input  logic [9:0]  DrawX,
    input  logic [9:0]  DrawY,
    
    //world-space gameplay inputs
    input  logic [10:0] camera_x, camera_y,
    input  logic [10:0] p1_x, p1_y,
    input  logic [10:0] p2_x, p2_y,
    input  logic [2:0]  p1_dir,
    input  logic [2:0]  p2_dir,         
    input  logic [10:0] zombie_x [10],
    input  logic [10:0] zombie_y [10],
    input  logic [9:0]  zombie_active,
    
    //bullet positions and active mask
    input  logic [10:0] bullet_x [20],
    input  logic [10:0] bullet_y [20],
    input  logic [19:0] bullet_active,
    
    //weapon drops and pickup ui state
    input  logic [10:0] weapon_drop_x [4],
    input  logic [10:0] weapon_drop_y [4],
    input  logic [1:0]  weapon_drop_type [4], //0:revolver, 1:shotgun, 2:uzi
    input  logic [3:0]  weapon_drop_active,   //active mask for four drops

    input  logic [2:0]  zombie_hp [10],
    input  logic [10:0] pickup_x [5],
    input  logic [10:0] pickup_y [5],
    input  logic [4:0]  pickup_active,
    
    //ui inputs
    input  logic [7:0]  kill_count,
    input  logic [3:0]  p1_hp,
    input  logic [3:0]  p2_hp,

    output logic [3:0]  Red, Green, Blue
);

    //convert the scaled vga pixel to a 12-bit world coordinate
    logic [11:0] world_draw_x, world_draw_y;
    assign world_draw_x = {3'b000, DrawX[9:1]} + {1'b0, camera_x};
    assign world_draw_y = {3'b000, DrawY[9:1]} + {1'b0, camera_y};

    //tile map: upper nibble is object type, lower nibble is sprite index
    logic [7:0] tile_map [0:127][0:127];

    //tile placement helper tasks
    task automatic place_building(input int x, input int y);
        for(int dy=0; dy<4; dy++) for(int dx=0; dx<3; dx++) tile_map[y+dy][x+dx] = {4'd4, 4'(dy * 3 + dx)};
    endtask

    task automatic place_building_small(input int x, input int y);
        for(int dy=0; dy<2; dy++) for(int dx=0; dx<3; dx++) tile_map[y+dy][x+dx] = {4'd6, 4'(dy * 3 + dx)};
    endtask

    task automatic place_house(input int x, input int y);
        for(int dy=0; dy<3; dy++) for(int dx=0; dx<3; dx++) tile_map[y+dy][x+dx] = {4'd7, 4'(dy * 3 + dx)};
    endtask

    task automatic place_tree(input int x, input int y);
        for(int dy=0; dy<3; dy++) for(int dx=0; dx<3; dx++) tile_map[y+dy][x+dx] = {4'd3, 4'(dy * 3 + dx)};
    endtask

    task automatic place_tree2(input int x, input int y);
        tile_map[y][x]   = {4'd8, 4'd0}; 
        tile_map[y+1][x] = {4'd8, 4'd3}; 
        tile_map[y+2][x] = {4'd8, 4'd6}; 
    endtask

    task automatic place_trash1(input int x, input int y); tile_map[y][x] = {4'd9, 4'd0}; endtask
    task automatic place_trash2(input int x, input int y); tile_map[y][x] = {4'd10, 4'd0}; endtask
    task automatic place_manhole(input int x, input int y); tile_map[y][x] = {4'd11, 4'd0}; endtask
    task automatic place_stopsign(input int x, input int y); tile_map[y][x] = {4'd12, 4'd0}; endtask
    task automatic place_trafficlight(input int x, input int y);
        tile_map[y][x]   = {4'd13, 4'd0}; 
        tile_map[y+1][x] = {4'd13, 4'd3}; 
    endtask

    //road placement helpers
    task automatic place_road_h(input int x, input int y, input int length);
        for(int dx=0; dx<length; dx++) begin
            tile_map[y][x+dx]   = {4'd5, 4'd1}; 
            tile_map[y+1][x+dx] = {4'd5, 4'd4}; 
            tile_map[y+2][x+dx] = {4'd5, 4'd8}; 
        end
    endtask

    task automatic place_road_v(input int x, input int y, input int length);
        for(int dy=0; dy<length; dy++) begin
            tile_map[y+dy][x]   = {4'd5, 4'd3}; 
            tile_map[y+dy][x+1] = {4'd5, 4'd5}; 
            tile_map[y+dy][x+2] = {4'd5, 4'd6}; 
        end
    endtask

    task automatic place_cross(input int x, input int y);
        for(int dy=0; dy<3; dy++) for(int dx=0; dx<3; dx++) tile_map[y+dy][x+dx] = {4'd5, 4'd4}; 
        tile_map[y][x]     = {4'd5, 4'd0}; 
        tile_map[y][x+2]   = {4'd5, 4'd2}; 
        tile_map[y+2][x]   = {4'd5, 4'd7}; 
        tile_map[y+2][x+2] = {4'd5, 4'd9}; 
    endtask

    //district decoration helpers
    task automatic place_mixed_block(input int x, input int y);
        place_building(x, y);            
        place_building_small(x+4, y+2); 
        place_house(x+8, y+1);          
        place_building(x+12, y);        
    endtask

    task automatic decorate_cross(input int x, input int y);
        place_trafficlight(x-1, y-2); 
        place_trafficlight(x+3, y+2); 
        place_stopsign(x+3, y-1);
        place_stopsign(x-1, y+3);
        place_manhole(x+1, y+1);
    endtask

    task automatic place_forest(input int x, input int y);
        place_tree(x, y); place_tree2(x+4, y+1); place_tree(x+6, y-1);
        place_tree2(x+1, y+4); place_tree(x+4, y+5);
    endtask

    task automatic place_park(input int x, input int y);
        place_tree(x, y); place_tree(x+4, y); 
        place_tree2(x+8, y); place_tree2(x+10, y);
        place_tree(x+2, y+4); place_tree(x+7, y+4);
    endtask

    initial begin
        //fill the map with grass and border fences
        for (int i = 0; i < 128; i++) for (int j = 0; j < 128; j++) tile_map[j][i] = {4'd0, 4'((j%4)*4 + (i%4))};
        for (int i = 0; i < 126; i += 3) begin
            for(int dy=0; dy<2; dy++) for(int dx=0; dx<3; dx++) begin
                tile_map[dy][i+dx] = {4'd1, 4'(dy * 3 + dx)}; 
                tile_map[126+dy][i+dx] = {4'd1, 4'(dy * 3 + dx)}; 
            end
        end
        for (int j = 2; j < 126; j += 5) begin
            for(int dy=0; dy<5; dy++) begin
                tile_map[j+dy][0] = {4'd2, 4'(dy)}; tile_map[j+dy][127] = {4'd2, 4'(dy)}; 
            end
        end
        
        //place the main 3x3-road grid
        place_road_h(10, 20, 100); place_road_h(10, 50, 100); place_road_h(10, 80, 100); 
        place_road_v(20, 10, 100); place_road_v(50, 10, 100); place_road_v(80, 10, 100); 

        //add intersections, stop signs, traffic lights, and manholes
        place_cross(20, 20); decorate_cross(20, 20); place_cross(50, 20); decorate_cross(50, 20); place_cross(80, 20); decorate_cross(80, 20);
        place_cross(20, 50); decorate_cross(20, 50); place_cross(50, 50); decorate_cross(50, 50); place_cross(80, 50); decorate_cross(80, 50);
        place_cross(20, 80); decorate_cross(20, 80); place_cross(50, 80); decorate_cross(50, 80); place_cross(80, 80); decorate_cross(80, 80);

        //add city blocks
        place_mixed_block(25, 25); place_house(40, 25); 
        place_building_small(55, 25); place_house(65, 25); place_building(72, 25);
        place_park(85, 25);
        place_building(25, 55); place_building_small(30, 65); place_house(40, 55);
        place_mixed_block(55, 55); place_building_small(72, 55);
        place_park(85, 55); 
        place_mixed_block(25, 85); 
        place_house(55, 85); place_house(60, 85); place_building(65, 85);

        //add outer scenery and park areas
        place_forest(5, 5); place_house(30, 8); place_forest(40, 5); place_house(60, 8); place_forest(70, 5); place_house(90, 8); place_forest(105, 5);
        place_forest(5, 105); place_house(30, 95); place_forest(40, 105); place_house(60, 95); place_forest(70, 105); place_house(90, 95); place_forest(105, 105);
        place_forest(5, 35); place_forest(5, 65); place_house(5, 90);
        place_forest(105, 35); place_forest(105, 65); place_house(105, 90);

        //add props and small details
        place_trash1(23, 28); place_trash2(24, 28); place_trash1(48, 55);
        place_trash2(60, 48); place_trash1(82, 30); place_trash2(100, 53);
        place_trash1(35, 75); place_trash2(70, 82); place_trash1(55, 90);
        place_trash2(15, 15); place_trash1(95, 95); place_trash2(45, 105);
        place_manhole(25, 21); place_manhole(65, 51); place_manhole(81, 65);
        place_manhole(35, 81); place_manhole(21, 35); place_manhole(51, 90);
    end

    //tile coordinate and rom address setup
    logic [7:0] tile_x, tile_y; 
    logic [3:0] local_x, local_y;
    assign tile_x  = world_draw_x[11:4];  
    assign tile_y  = world_draw_y[11:4];  
    assign local_x = world_draw_x[3:0];  
    assign local_y = world_draw_y[3:0];  

    logic [7:0] current_tile_id;
    always_comb begin
        if (tile_x < 128 && tile_y < 128) current_tile_id = tile_map[tile_y][tile_x];
        else current_tile_id = 8'h00; 
    end

    logic [3:0] obj_type; 
    logic [3:0] obj_idx;
    assign obj_type = current_tile_id[7:4];
    assign obj_idx  = current_tile_id[3:0];

    logic [6:0] obj_x_offset, obj_y_offset;
    always_comb begin
        case (obj_idx)
            4'd0:  begin obj_x_offset = 0;  obj_y_offset = 0;  end
            4'd1:  begin obj_x_offset = 16; obj_y_offset = 0;  end
            4'd2:  begin obj_x_offset = 32; obj_y_offset = 0;  end
            4'd3:  begin obj_x_offset = 0;  obj_y_offset = 16; end
            4'd4:  begin obj_x_offset = 16; obj_y_offset = 16; end
            4'd5:  begin obj_x_offset = 32; obj_y_offset = 16; end
            4'd6:  begin obj_x_offset = 0;  obj_y_offset = 32; end
            4'd7:  begin obj_x_offset = 16; obj_y_offset = 32; end
            4'd8:  begin obj_x_offset = 32; obj_y_offset = 32; end
            4'd9:  begin obj_x_offset = 0;  obj_y_offset = 48; end
            4'd10: begin obj_x_offset = 16; obj_y_offset = 48; end
            4'd11: begin obj_x_offset = 32; obj_y_offset = 48; end
            default: begin obj_x_offset = 0; obj_y_offset = 0; end
        endcase
    end

    logic [3:0] bg_grass_idx;
    assign bg_grass_idx = {tile_y[1:0], tile_x[1:0]}; 

    logic [12:0] addr_grass, addr_fence_f, addr_fence_s, addr_tree, addr_bldg;
    logic [11:0] addr_road, addr_bldg_s, addr_house; 
    logic [9:0]  addr_tree2;
    logic [8:0]  addr_trafficlight;
    logic [7:0]  addr_trash1, addr_trash2, addr_manhole, addr_stopsign;
    logic [5:0]  road_tex_x, road_tex_y;

    always_comb begin
        addr_grass   = (bg_grass_idx[3:2] * 16 + local_y) * 64 + (bg_grass_idx[1:0] * 16 + local_x);
        addr_fence_f = (obj_y_offset + local_y) * 48 + (obj_x_offset + local_x);
        addr_fence_s = (obj_idx * 16 + local_y) * 16 + local_x;
        addr_tree    = (obj_y_offset + local_y) * 48 + (obj_x_offset + local_x);
        addr_bldg    = (obj_y_offset + local_y) * 48 + (obj_x_offset + local_x);
        addr_bldg_s  = (obj_y_offset + local_y) * 48 + (obj_x_offset + local_x);
        addr_house   = (obj_y_offset + local_y) * 48 + (obj_x_offset + local_x);
        addr_tree2   = (obj_y_offset + local_y) * 16 + local_x;
        addr_trash1  = local_y * 16 + local_x;
        addr_trash2  = local_y * 16 + local_x;
        addr_manhole = local_y * 16 + local_x;
        addr_stopsign= local_y * 16 + local_x;
        addr_trafficlight = (obj_y_offset + local_y) * 16 + local_x;
        
        //road texture coordinates
        road_tex_x = 0; road_tex_y = 0;
        if (obj_type == 4'd5) begin
            case (obj_idx)
                4'd0: begin road_tex_x = local_x;      road_tex_y = local_y;      end
                4'd1: begin road_tex_x = 16 + local_x; road_tex_y = local_y;      end
                4'd2: begin road_tex_x = 32 + local_x; road_tex_y = local_y;      end
                4'd3: begin road_tex_x = local_x;      road_tex_y = 16 + local_y; end
                4'd4: begin road_tex_x = 16 + local_x; road_tex_y = 16 + local_y; end
                4'd5: begin road_tex_x = 16 + local_y; road_tex_y = 16 + (4'd15 - local_x); end 
                4'd6: begin road_tex_x = 32 + local_x; road_tex_y = 16 + local_y; end
                4'd7: begin road_tex_x = local_x;      road_tex_y = 32 + local_y; end
                4'd8: begin road_tex_x = 16 + local_x; road_tex_y = 32 + local_y; end
                4'd9: begin road_tex_x = 32 + local_x; road_tex_y = 32 + local_y; end
                default: begin road_tex_x = 16 + local_x; road_tex_y = 16 + local_y; end 
            endcase
        end
        addr_road = road_tex_y * 6'd48 + road_tex_x;
    end

    //rom outputs for the 14 sprite sources
    logic [3:0] idx_grass, idx_fence_f, idx_fence_s, idx_tree, idx_bldg, idx_road;
    logic [3:0] idx_bldg_s, idx_house, idx_tree2, idx_trash1, idx_trash2, idx_manhole, idx_stopsign, idx_trafficlight;
    
    logic [3:0] r_grass, g_grass, b_grass; logic [3:0] r_fen_f, g_fen_f, b_fen_f; logic [3:0] r_fen_s, g_fen_s, b_fen_s;
    logic [3:0] r_tree, g_tree, b_tree; logic [3:0] r_bldg, g_bldg, b_bldg; logic [3:0] r_road, g_road, b_road; 
    logic [3:0] r_bldg_s, g_bldg_s, b_bldg_s; logic [3:0] r_house, g_house, b_house; logic [3:0] r_tree2, g_tree2, b_tree2;
    logic [3:0] r_tr1, g_tr1, b_tr1; logic [3:0] r_tr2, g_tr2, b_tr2;
    logic [3:0] r_manhole, g_manhole, b_manhole; logic [3:0] r_stop, g_stop, b_stop; logic [3:0] r_tl, g_tl, b_tl;

    Grass_rom r1(.clka(clk), .ena(1'b1), .addra(addr_grass), .douta(idx_grass)); Grass_palette p1(.index(idx_grass), .red(r_grass), .green(g_grass), .blue(b_grass));
    Fence_Front_rom r2(.clka(clk), .ena(1'b1), .addra(addr_fence_f), .douta(idx_fence_f)); Fence_Front_palette p2(.index(idx_fence_f), .red(r_fen_f), .green(g_fen_f), .blue(b_fen_f));
    Fence_Side_rom r3(.clka(clk), .ena(1'b1), .addra(addr_fence_s), .douta(idx_fence_s)); Fence_Side_palette p3(.index(idx_fence_s), .red(r_fen_s), .green(g_fen_s), .blue(b_fen_s));
    Tree_rom r4(.clka(clk), .ena(1'b1), .addra(addr_tree), .douta(idx_tree)); Tree_palette p4(.index(idx_tree), .red(r_tree), .green(g_tree), .blue(b_tree));
    Building_rom r5(.clka(clk), .ena(1'b1), .addra(addr_bldg), .douta(idx_bldg)); Building_palette p5(.index(idx_bldg), .red(r_bldg), .green(g_bldg), .blue(b_bldg));
    Road_rom r6(.clka(clk), .ena(1'b1), .addra(addr_road), .douta(idx_road)); Road_palette p6(.index(idx_road), .red(r_road), .green(g_road), .blue(b_road));
    
    Building_Small_rom r7(.clka(clk), .ena(1'b1), .addra(addr_bldg_s), .douta(idx_bldg_s)); Building_Small_palette p7(.index(idx_bldg_s), .red(r_bldg_s), .green(g_bldg_s), .blue(b_bldg_s));
    House_rom r8(.clka(clk), .ena(1'b1), .addra(addr_house), .douta(idx_house)); House_palette p8(.index(idx_house), .red(r_house), .green(g_house), .blue(b_house));
    Tree2_rom r9(.clka(clk), .ena(1'b1), .addra(addr_tree2), .douta(idx_tree2)); Tree2_palette p9(.index(idx_tree2), .red(r_tree2), .green(g_tree2), .blue(b_tree2));
    Trash1_rom r10(.clka(clk), .ena(1'b1), .addra(addr_trash1), .douta(idx_trash1)); Trash1_palette p10(.index(idx_trash1), .red(r_tr1), .green(g_tr1), .blue(b_tr1));
    Trash2_rom r11(.clka(clk), .ena(1'b1), .addra(addr_trash2), .douta(idx_trash2)); Trash2_palette p11(.index(idx_trash2), .red(r_tr2), .green(g_tr2), .blue(b_tr2));
    Manhole_rom r12(.clka(clk), .ena(1'b1), .addra(addr_manhole), .douta(idx_manhole)); Manhole_palette p12(.index(idx_manhole), .red(r_manhole), .green(g_manhole), .blue(b_manhole));
    StopSign_rom r13(.clka(clk), .ena(1'b1), .addra(addr_stopsign), .douta(idx_stopsign)); StopSign_palette p13(.index(idx_stopsign), .red(r_stop), .green(g_stop), .blue(b_stop));
    TrafficLight_rom r14(.clka(clk), .ena(1'b1), .addra(addr_trafficlight), .douta(idx_trafficlight)); TrafficLight_palette p14(.index(idx_trafficlight), .red(r_tl), .green(g_tl), .blue(b_tl));

    //select foreground tile color, then fall back to grass for transparent pixels
    logic [3:0] fg_R, fg_G, fg_B;
    always_comb begin
        case (obj_type)
            4'd1: begin fg_R = r_fen_f; fg_G = g_fen_f; fg_B = b_fen_f; end
            4'd2: begin fg_R = r_fen_s; fg_G = g_fen_s; fg_B = b_fen_s; end
            4'd3: begin fg_R = r_tree;  fg_G = g_tree;  fg_B = b_tree;  end
            4'd4: begin fg_R = r_bldg;  fg_G = g_bldg;  fg_B = b_bldg;  end
            4'd5: begin fg_R = r_road;  fg_G = g_road;  fg_B = b_road;  end 
            4'd6: begin fg_R = r_bldg_s;fg_G = g_bldg_s;fg_B = b_bldg_s;end
            4'd7: begin fg_R = r_house; fg_G = g_house; fg_B = b_house; end
            4'd8: begin fg_R = r_tree2; fg_G = g_tree2; fg_B = b_tree2; end
            4'd9: begin fg_R = r_tr1;   fg_G = g_tr1;   fg_B = b_tr1;   end
            4'd10:begin fg_R = r_tr2;   fg_G = g_tr2;   fg_B = b_tr2;   end
            4'd11:begin fg_R = r_manhole;fg_G = g_manhole;fg_B = b_manhole;end
            4'd12:begin fg_R = r_stop;  fg_G = g_stop;  fg_B = b_stop;  end
            4'd13:begin fg_R = r_tl;    fg_G = g_tl;    fg_B = b_tl;    end
            default:begin fg_R = r_grass; fg_G = g_grass; fg_B = b_grass; end 
        endcase
    end

    logic [3:0] bg_R, bg_G, bg_B;
    always_comb begin
        if (obj_type != 4'd0 && !(fg_R == 4'h0 && fg_G == 4'hF && fg_B == 4'h0)) begin
            bg_R = fg_R; bg_G = fg_G; bg_B = fg_B;
        end else begin
            bg_R = r_grass; bg_G = g_grass; bg_B = b_grass;
        end
    end

    //zombie sprite lookup for ten slots
    logic [7:0] z_addr_array [10];
    logic [3:0] z_index_array [10];
    logic [3:0] z_r_array [10], z_g_array [10], z_b_array [10];

    always_comb begin
        for (int i = 0; i < 10; i++) begin
            if (zombie_active[i] && 
                world_draw_x >= 12'(zombie_x[i]) && world_draw_x < 12'(zombie_x[i]) + 16 &&
                world_draw_y >= 12'(zombie_y[i]) && world_draw_y < 12'(zombie_y[i]) + 16) begin
                z_addr_array[i] = (world_draw_x - 12'(zombie_x[i])) + (world_draw_y - 12'(zombie_y[i])) * 16;
            end else begin
                z_addr_array[i] = 8'd0; 
            end
        end
    end

    genvar g_z;
    generate
        for (g_z = 0; g_z < 10; g_z++) begin : zombie_hardware_gen
            zombie_rom z_rom_inst (.clka(clk), .ena(1'b1), .addra(z_addr_array[g_z]), .douta(z_index_array[g_z]));
            zombie_palette z_pal_inst (.index(z_index_array[g_z]), .red(z_r_array[g_z]), .green(z_g_array[g_z]), .blue(z_b_array[g_z]));
        end
    endgenerate

    logic is_valid_zombie_pixel; 
    logic [3:0] final_z_r, final_z_g, final_z_b;
    always_comb begin
        is_valid_zombie_pixel = 1'b0; final_z_r = 4'h0; final_z_g = 4'h0; final_z_b = 4'h0;
        for (int k = 0; k < 10; k++) begin
            if (zombie_active[k] && 
                world_draw_x >= 12'(zombie_x[k]) && world_draw_x < 12'(zombie_x[k]) + 16 &&
                world_draw_y >= 12'(zombie_y[k]) && world_draw_y < 12'(zombie_y[k]) + 16) begin
                if (!(z_r_array[k] == 4'h0 && z_g_array[k] == 4'hF && z_b_array[k] == 4'h0)) begin
                    is_valid_zombie_pixel = 1'b1;
                    final_z_r = z_r_array[k]; final_z_g = z_g_array[k]; final_z_b = z_b_array[k];
                end
            end
        end
    end

    //zombie hp bar: 18x4 pixels, drawn just above each active zombie
    logic is_valid_zombie_hp_bar;
    logic [3:0] zombie_hp_bar_r, zombie_hp_bar_g, zombie_hp_bar_b;
    always_comb begin
        is_valid_zombie_hp_bar = 1'b0;
        zombie_hp_bar_r = 4'h0;
        zombie_hp_bar_g = 4'h0;
        zombie_hp_bar_b = 4'h0;

        for (int k = 0; k < 10; k++) begin
            if (zombie_active[k] && zombie_y[k] >= 11'd6 &&
                world_draw_x >= 12'(zombie_x[k]) - 12'd1 &&
                world_draw_x <  12'(zombie_x[k]) + 12'd17 &&
                world_draw_y >= 12'(zombie_y[k]) - 12'd6 &&
                world_draw_y <  12'(zombie_y[k]) - 12'd2) begin

                logic [4:0] bar_x;
                logic [2:0] bar_y;
                logic [4:0] fill_width;

                bar_x = world_draw_x - (12'(zombie_x[k]) - 12'd1);
                bar_y = world_draw_y - (12'(zombie_y[k]) - 12'd6);
                fill_width = (zombie_hp[k] >= 3'd5) ? 5'd16 : ({2'b00, zombie_hp[k]} * 5'd3);

                is_valid_zombie_hp_bar = 1'b1;
                if (bar_x == 5'd0 || bar_x == 5'd17 || bar_y == 3'd0 || bar_y == 3'd3) begin
                    zombie_hp_bar_r = 4'h0;
                    zombie_hp_bar_g = 4'h0;
                    zombie_hp_bar_b = 4'h0;
                end else if ((bar_x - 5'd1) < fill_width) begin
                    zombie_hp_bar_r = 4'h2;
                    zombie_hp_bar_g = 4'hF;
                    zombie_hp_bar_b = 4'h2;
                end else begin
                    zombie_hp_bar_r = 4'hF;
                    zombie_hp_bar_g = 4'h1;
                    zombie_hp_bar_b = 4'h1;
                end
            end
        end
    end

    //player sprites
    logic [3:0] p1_local_x, p1_local_y; logic [10:0] p1_addr; logic [3:0] p1_idx; logic [3:0] p1_r, p1_g, p1_b;
    logic [3:0] p2_local_x, p2_local_y; logic [10:0] p2_addr; logic [3:0] p2_idx; logic [3:0] p2_r, p2_g, p2_b;

    assign p1_local_x = world_draw_x - 12'(p1_x); assign p1_local_y = world_draw_y - 12'(p1_y);
    assign p2_local_x = world_draw_x - 12'(p2_x); assign p2_local_y = world_draw_y - 12'(p2_y);

    assign p1_addr = {p1_local_y[3:0], p1_dir[2:0], p1_local_x[3:0]};
    assign p2_addr = {p2_local_y[3:0], p2_dir[2:0], p2_local_x[3:0]};

    human_rom rom_p1 (.clka(clk), .ena(1'b1), .addra(p1_addr), .douta(p1_idx)); human_palette pal_p1 (.index(p1_idx), .red(p1_r), .green(p1_g), .blue(p1_b));
    human_rom rom_p2 (.clka(clk), .ena(1'b1), .addra(p2_addr), .douta(p2_idx)); human_palette pal_p2 (.index(p2_idx), .red(p2_r), .green(p2_g), .blue(p2_b));

    //health pickup rendering
    logic is_valid_pickup_hp; logic [3:0] pickup_r, pickup_g, pickup_b;
    always_comb begin
        is_valid_pickup_hp = 1'b0; pickup_r = 4'h0; pickup_g = 4'h0; pickup_b = 4'h0;
        for (int p = 0; p < 5; p++) begin
            if (pickup_active[p] && world_draw_x >= 12'(pickup_x[p]) && world_draw_x < 12'(pickup_x[p]) + 16 && world_draw_y >= 12'(pickup_y[p]) && world_draw_y < 12'(pickup_y[p]) + 16) begin
                logic [3:0] local_pk_x, local_pk_y;
                local_pk_x = world_draw_x - 12'(pickup_x[p]); local_pk_y = world_draw_y - 12'(pickup_y[p]);
                if (local_pk_x >= 4 && local_pk_x <= 11 && local_pk_y >= 4 && local_pk_y <= 11) begin
                    is_valid_pickup_hp = 1'b1;
                    if ((local_pk_x >= 6 && local_pk_x <= 9 && local_pk_y >= 7 && local_pk_y <= 8) || (local_pk_y >= 6 && local_pk_y <= 9 && local_pk_x >= 7 && local_pk_x <= 8)) begin pickup_r = 4'hF; pickup_g = 4'h0; pickup_b = 4'h0; end 
                    else begin pickup_r = 4'hF; pickup_g = 4'hF; pickup_b = 4'hF; end
                end
            end
        end
    end

    //weapon drop rendering from 16x16 rom sprites
    logic is_valid_weapon_drop;
    logic [3:0] weapon_drop_r, weapon_drop_g, weapon_drop_b;
    
    logic [7:0] weapon_rom_addr;
    logic [3:0] rev_idx, shot_idx, uzi_idx;
    logic [3:0] r_rev, g_rev, b_rev;
    logic [3:0] r_shot, g_shot, b_shot;
    logic [3:0] r_uzi, g_uzi, b_uzi;

    Revolver_rom r_rev_inst(.clka(clk), .ena(1'b1), .addra(weapon_rom_addr), .douta(rev_idx)); Revolver_palette p_rev_inst(.index(rev_idx), .red(r_rev), .green(g_rev), .blue(b_rev));
    ShotGun_rom r_shot_inst(.clka(clk), .ena(1'b1), .addra(weapon_rom_addr), .douta(shot_idx)); ShotGun_palette p_shot_inst(.index(shot_idx), .red(r_shot), .green(g_shot), .blue(b_shot));
    Uzi_rom r_uzi_inst(.clka(clk), .ena(1'b1), .addra(weapon_rom_addr), .douta(uzi_idx)); Uzi_palette p_uzi_inst(.index(uzi_idx), .red(r_uzi), .green(g_uzi), .blue(b_uzi));

    always_comb begin
        is_valid_weapon_drop = 1'b0;
        weapon_drop_r = 4'h0; weapon_drop_g = 4'h0; weapon_drop_b = 4'h0;
        weapon_rom_addr = 8'd0; 

        for (int p = 0; p < 4; p++) begin
            if (weapon_drop_active[p] && 
                world_draw_x >= 12'(weapon_drop_x[p]) && world_draw_x < 12'(weapon_drop_x[p]) + 16 && 
                world_draw_y >= 12'(weapon_drop_y[p]) && world_draw_y < 12'(weapon_drop_y[p]) + 16) begin
                
                logic [3:0] local_wx, local_wy;
                local_wx = world_draw_x - 12'(weapon_drop_x[p]);
                local_wy = world_draw_y - 12'(weapon_drop_y[p]);
                weapon_rom_addr = local_wy * 16 + local_wx;
                
                if (weapon_drop_type[p] == 2'd0) begin
                    if (!(r_rev == 4'h0 && g_rev == 4'hF && b_rev == 4'h0)) begin
                        is_valid_weapon_drop = 1'b1;
                        weapon_drop_r = r_rev; weapon_drop_g = g_rev; weapon_drop_b = b_rev;
                    end
                end else if (weapon_drop_type[p] == 2'd1) begin
                    if (!(r_shot == 4'h0 && g_shot == 4'hF && b_shot == 4'h0)) begin
                        is_valid_weapon_drop = 1'b1;
                        weapon_drop_r = r_shot; weapon_drop_g = g_shot; weapon_drop_b = b_shot;
                    end
                end else if (weapon_drop_type[p] == 2'd2) begin
                    if (!(r_uzi == 4'h0 && g_uzi == 4'hF && b_uzi == 4'h0)) begin
                        is_valid_weapon_drop = 1'b1;
                        weapon_drop_r = r_uzi; weapon_drop_g = g_uzi; weapon_drop_b = b_uzi;
                    end
                end
            end
        end
    end

    //kill counter ui and player hp ui
    localparam UI_ICON_X = 10'd5; localparam UI_ICON_Y = 10'd5; localparam UI_TEXT_X = 10'd25; localparam UI_TEXT_Y = 10'd10; localparam CHAR_W = 4;         
    localparam HP1_UI_X = 10'd5; localparam HP1_UI_Y = 10'd25; localparam HP2_UI_X = 10'd5; localparam HP2_UI_Y = 10'd45; 

    logic is_ui_icon_area, is_ui_text_area, is_hp1_ui_area, is_hp2_ui_area;
    assign is_ui_icon_area = (DrawX >= UI_ICON_X && DrawX < UI_ICON_X + 16 && DrawY >= UI_ICON_Y && DrawY < UI_ICON_Y + 16);
    assign is_ui_text_area = (DrawX >= UI_TEXT_X && DrawX < UI_TEXT_X + (CHAR_W * 6) && DrawY >= UI_TEXT_Y && DrawY < UI_TEXT_Y + 7);
    assign is_hp1_ui_area = (DrawX >= HP1_UI_X && DrawX < HP1_UI_X + 80 && DrawY >= HP1_UI_Y && DrawY < HP1_UI_Y + 16);
    assign is_hp2_ui_area = (DrawX >= HP2_UI_X && DrawX < HP2_UI_X + 80 && DrawY >= HP2_UI_Y && DrawY < HP2_UI_Y + 16);

    logic [7:0] ui_icon_addr; logic [3:0] ui_icon_index; logic [3:0] ui_icon_r, ui_icon_g, ui_icon_b;
    assign ui_icon_addr = (DrawY - UI_ICON_Y) * 16 + (DrawX - UI_ICON_X);
    UI_Zombie_rom ui_zmb_rom (.clka(clk), .ena(1'b1), .addra(ui_icon_addr), .douta(ui_icon_index)); UI_Zombie_palette ui_zmb_pal (.index(ui_icon_index), .red(ui_icon_r), .green(ui_icon_g), .blue(ui_icon_b));

    function automatic logic get_font_pixel(input [3:0] char, input [2:0] lx, input [2:0] ly);
        logic [2:0] row_bits;
        begin
            case (char)
                4'd0: case (ly) 0:row_bits=3'b111; 1:row_bits=3'b101; 2:row_bits=3'b101; 3:row_bits=3'b101; 4:row_bits=3'b111; default:row_bits=3'b000; endcase
                4'd1: case (ly) 0:row_bits=3'b010; 1:row_bits=3'b110; 2:row_bits=3'b010; 3:row_bits=3'b010; 4:row_bits=3'b111; default:row_bits=3'b000; endcase
                4'd2: case (ly) 0:row_bits=3'b111; 1:row_bits=3'b001; 2:row_bits=3'b111; 3:row_bits=3'b100; 4:row_bits=3'b111; default:row_bits=3'b000; endcase
                4'd3: case (ly) 0:row_bits=3'b111; 1:row_bits=3'b001; 2:row_bits=3'b111; 3:row_bits=3'b001; 4:row_bits=3'b111; default:row_bits=3'b000; endcase
                4'd4: case (ly) 0:row_bits=3'b101; 1:row_bits=3'b101; 2:row_bits=3'b111; 3:row_bits=3'b001; 4:row_bits=3'b001; default:row_bits=3'b000; endcase
                4'd5: case (ly) 0:row_bits=3'b111; 1:row_bits=3'b100; 2:row_bits=3'b111; 3:row_bits=3'b001; 4:row_bits=3'b111; default:row_bits=3'b000; endcase
                4'd6: case (ly) 0:row_bits=3'b111; 1:row_bits=3'b100; 2:row_bits=3'b111; 3:row_bits=3'b101; 4:row_bits=3'b111; default:row_bits=3'b000; endcase
                4'd7: case (ly) 0:row_bits=3'b111; 1:row_bits=3'b001; 2:row_bits=3'b010; 3:row_bits=3'b010; 4:row_bits=3'b010; default:row_bits=3'b000; endcase
                4'd8: case (ly) 0:row_bits=3'b111; 1:row_bits=3'b101; 2:row_bits=3'b111; 3:row_bits=3'b101; 4:row_bits=3'b111; default:row_bits=3'b000; endcase
                4'd9: case (ly) 0:row_bits=3'b111; 1:row_bits=3'b101; 2:row_bits=3'b111; 3:row_bits=3'b001; 4:row_bits=3'b111; default:row_bits=3'b000; endcase
                4'd10:case (ly) 0:row_bits=3'b001; 1:row_bits=3'b010; 2:row_bits=3'b010; 3:row_bits=3'b100; 4:row_bits=3'b100; default:row_bits=3'b000; endcase
                default: row_bits = 3'b000;
            endcase
            if (lx >= 0 && lx <= 2) return row_bits[2 - lx];
            else return 1'b0;
        end
    endfunction

    logic [3:0] digit_tens, digit_units; logic is_text_pixel; logic [3:0] text_r, text_g, text_b; logic [5:0] tx; logic [3:0] ty;
    assign digit_tens  = (kill_count / 8'd10) % 4'd10; assign digit_units = (kill_count % 8'd10);
    always_comb begin
        is_text_pixel = 1'b0; text_r = 4'hF; text_g = 4'hF; text_b = 4'hF; 
        if (is_ui_text_area) begin
            tx = DrawX - UI_TEXT_X; ty = DrawY - UI_TEXT_Y;
            if      (tx >= CHAR_W*0 && tx < CHAR_W*0+3) begin if (get_font_pixel(digit_tens, 3'(tx - CHAR_W*0), 3'(ty))) is_text_pixel = 1; end
            else if (tx >= CHAR_W*1 && tx < CHAR_W*1+3) begin if (get_font_pixel(digit_units, 3'(tx - CHAR_W*1), 3'(ty))) is_text_pixel = 1; end
            else if (tx >= CHAR_W*2 && tx < CHAR_W*2+3) begin if (get_font_pixel(4'd10,        3'(tx - CHAR_W*2), 3'(ty))) is_text_pixel = 1; end 
            else if (tx >= CHAR_W*3 && tx < CHAR_W*3+3) begin if (get_font_pixel(4'd1,         3'(tx - CHAR_W*3), 3'(ty))) is_text_pixel = 1; end 
            else if (tx >= CHAR_W*4 && tx < CHAR_W*4+3) begin if (get_font_pixel(4'd0,         3'(tx - CHAR_W*4), 3'(ty))) is_text_pixel = 1; end 
            else if (tx >= CHAR_W*5 && tx < CHAR_W*5+3) begin if (get_font_pixel(4'd0,         3'(tx - CHAR_W*5), 3'(ty))) is_text_pixel = 1; end 
        end
    end
    
    logic is_ui_visible; logic [3:0] final_ui_r, final_ui_g, final_ui_b;
    always_comb begin
        is_ui_visible = 1'b0; final_ui_r = 4'h0; final_ui_g = 4'h0; final_ui_b = 4'h0;
        if (is_ui_icon_area) begin
            if (!(ui_icon_r == 4'h0 && ui_icon_g == 4'hF && ui_icon_b == 4'h0)) begin is_ui_visible = 1'b1; final_ui_r = ui_icon_r; final_ui_g = ui_icon_g; final_ui_b = ui_icon_b; end
        end else if (is_text_pixel) begin is_ui_visible = 1'b1; final_ui_r = text_r; final_ui_g = text_g; final_ui_b = text_b; end
    end

    logic [6:0] hp_local_x; logic [3:0] hp_local_y; logic [2:0] heart_index; logic [3:0] heart_pixel_x;  
    always_comb begin
        if (is_hp1_ui_area) begin hp_local_x = DrawX - HP1_UI_X; hp_local_y = DrawY - HP1_UI_Y; end 
        else if (is_hp2_ui_area) begin hp_local_x = DrawX - HP2_UI_X; hp_local_y = DrawY - HP2_UI_Y; end 
        else begin hp_local_x = 0; hp_local_y = 0; end
    end
    assign heart_index = hp_local_x[6:4]; assign heart_pixel_x = hp_local_x[3:0]; 

    logic [1:0] heart_state; 
    always_comb begin
        if (is_hp1_ui_area) begin
            if (p1_hp >= (heart_index * 2) + 2) heart_state = 2'd2; else if (p1_hp == (heart_index * 2) + 1) heart_state = 2'd1; else heart_state = 2'd0; 
        end else if (is_hp2_ui_area) begin
            if (p2_hp >= (heart_index * 2) + 2) heart_state = 2'd2; else if (p2_hp == (heart_index * 2) + 1) heart_state = 2'd1; else heart_state = 2'd0; 
        end else heart_state = 2'd0;
    end

    logic [10:0] hp_rom_addr; logic [3:0] hp_color_index; logic [3:0] hp_r, hp_g, hp_b;
    always_comb begin
        if (is_hp1_ui_area || is_hp2_ui_area) hp_rom_addr = (hp_local_y * 8'd48) + {heart_state, 4'd0} + heart_pixel_x;
        else hp_rom_addr = 11'd0;
    end
    HealthBar_rom hp_rom_inst (.clka(clk), .ena(1'b1), .addra(hp_rom_addr), .douta(hp_color_index)); HealthBar_palette hp_pal_inst (.index(hp_color_index), .red(hp_r), .green(hp_g), .blue(hp_b));

    //bullet pixels
    logic [19:0] is_bullet_pixel;
    logic any_bullet;

    always_comb begin
        for (int i = 0; i < 20; i++) begin
            //draw each bullet as a 4x4 block by comparing coarser coordinate bits
            is_bullet_pixel[i] = bullet_active[i] &&
                                 (world_draw_x[11:2] == {1'b0, bullet_x[i][10:2]}) &&
                                 (world_draw_y[11:2] == {1'b0, bullet_y[i][10:2]});
        end
    end
    
    //or-reduce all 20 bullet pixels
    assign any_bullet = |is_bullet_pixel;

    logic game_over_active;
    logic [3:0] game_over_r, game_over_g, game_over_b;

    game_over_overlay game_over_inst (
        .clk(clk),
        .DrawX(DrawX),
        .DrawY(DrawY),
        .p1_hp(p1_hp),
        .p2_hp(p2_hp),
        .kill_count(kill_count),
        .active(game_over_active),
        .Red(game_over_r),
        .Green(game_over_g),
        .Blue(game_over_b)
    );

    //final color compositing mux
    always_comb begin
        //start with the background
        Red = bg_R; Green = bg_G; Blue = bg_B;

        //apply draw priority from topmost overlay down to background sprites
        if (game_over_active) begin
            Red = game_over_r; Green = game_over_g; Blue = game_over_b;

        end else if (is_ui_visible) begin
            Red = final_ui_r; Green = final_ui_g; Blue = final_ui_b;
            
        end else if ((is_hp1_ui_area && heart_index < 5) || (is_hp2_ui_area && heart_index < 5)) begin
            if (!(hp_r == 4'h0 && hp_g == 4'hF && hp_b == 4'h0)) begin //skip transparent pixels
                Red = hp_r; Green = hp_g; Blue = hp_b;
            end
            
        end else if (is_ui_text_area && is_text_pixel) begin
            Red = text_r; Green = text_g; Blue = text_b;

        end else if (is_valid_zombie_hp_bar) begin
            Red = zombie_hp_bar_r; Green = zombie_hp_bar_g; Blue = zombie_hp_bar_b;
            
        end else if (any_bullet) begin //bullets are drawn directly without a lut
            Red = 4'hF; Green = 4'hD; Blue = 4'h0; //yellow bullet
            
        end else if (is_valid_weapon_drop) begin
            Red = weapon_drop_r; Green = weapon_drop_g; Blue = weapon_drop_b;
            
        end else if (is_valid_pickup_hp) begin
            Red = pickup_r; Green = pickup_g; Blue = pickup_b;
            
        end else if (!(p1_r == 4'h0 && p1_g == 4'hF && p1_b == 4'h0) &&
                     world_draw_x >= 12'(p1_x) && world_draw_x < 12'(p1_x) + 16 &&
                     world_draw_y >= 12'(p1_y) && world_draw_y < 12'(p1_y) + 16) begin
            Red = p1_r; Green = p1_g; Blue = p1_b;
            
        end else if (!(p2_r == 4'h0 && p2_g == 4'hF && p2_b == 4'h0) &&
                     world_draw_x >= 12'(p2_x) && world_draw_x < 12'(p2_x) + 16 &&
                     world_draw_y >= 12'(p2_y) && world_draw_y < 12'(p2_y) + 16) begin
            Red = p2_r; Green = p2_g; Blue = p2_b;
            
        end else if (is_valid_zombie_pixel) begin
            Red = final_z_r; Green = final_z_g; Blue = final_z_b;
        end
    end

endmodule
