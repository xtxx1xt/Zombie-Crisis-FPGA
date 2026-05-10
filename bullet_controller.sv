module bullet_controller (
    input  logic        Clk,       
    input  logic        Reset,
    input  logic        vsync_in,  
    input  logic [31:0] keycode,   
    
    //player 1 position, facing, and weapon
    input  logic [10:0] p1_x,  
    input  logic [10:0] p1_y,  
    input  logic [2:0]  p1_dir,
    input  logic [1:0]  p1_weapon,   //00=revolver, 01=shotgun, 10=uzi

    //player 2 position, facing, and weapon
    input  logic [10:0] p2_x,  
    input  logic [10:0] p2_y,  
    input  logic [2:0]  p2_dir,
    input  logic [1:0]  p2_weapon,   //00=revolver, 01=shotgun, 10=uzi

    //collision feedback and player health
    input  logic [19:0] bullet_destroy_mask, 
    input  logic [3:0]  p1_hp,
    input  logic [3:0]  p2_hp,

    //bullet arrays: player 1 uses slots 0-9, player 2 uses slots 10-19
    output logic [10:0] bullet_x [20], 
    output logic [10:0] bullet_y [20], 
    output logic [19:0] bullet_active,
    output logic        shoot_pulse  
);

    //weapon identifiers
    localparam WEAPON_REV  = 2'd0;
    localparam WEAPON_SHOT = 2'd1;
    localparam WEAPON_UZI  = 2'd2;

    logic p1_alive, p2_alive;
    assign p1_alive = (p1_hp > 0);
    assign p2_alive = (p2_hp > 0);

    localparam MAX_X = 11'd2047;         
    localparam MAX_Y = 11'd2047;         

    logic vsync_prev;
    logic frame_tick;
    always_ff @(posedge Clk) vsync_prev <= vsync_in;
    assign frame_tick = (vsync_prev == 1'b1 && vsync_in == 1'b0);

    logic shoot_pulse_r;
    assign shoot_pulse = shoot_pulse_r;

    //fire button edge detection
    logic p1_fire_pressed, p1_fire_prev, p1_fire_edge;
    logic p2_fire_pressed, p2_fire_prev, p2_fire_edge;

    assign p1_fire_pressed = keycode[4];   //space
    assign p2_fire_pressed = keycode[12];  //enter
    
    always_ff @(posedge Clk) begin
        if (Reset) begin
            p1_fire_prev <= 1'b0;
            p2_fire_prev <= 1'b0;
        end else if (frame_tick) begin
            p1_fire_prev <= p1_fire_pressed;
            p2_fire_prev <= p2_fire_pressed;
        end
    end
    
    assign p1_fire_edge = p1_fire_pressed && !p1_fire_prev; 
    assign p2_fire_edge = p2_fire_pressed && !p2_fire_prev; 

    //uzi fire-rate limiter
    logic [3:0] p1_uzi_cd, p2_uzi_cd;
    logic p1_uzi_fire, p2_uzi_fire;

    always_ff @(posedge Clk) begin
        if (Reset) begin
            p1_uzi_cd <= 0; p1_uzi_fire <= 0;
            p2_uzi_cd <= 0; p2_uzi_fire <= 0;
        end else if (frame_tick) begin
            p1_uzi_fire <= 0;
            p2_uzi_fire <= 0;
            
            //p1 uzi
            if (p1_weapon == WEAPON_UZI && p1_fire_pressed && p1_alive) begin
                if (p1_uzi_cd == 0) begin p1_uzi_fire <= 1; p1_uzi_cd <= 4'd5; end 
                else p1_uzi_cd <= p1_uzi_cd - 1;
            end else p1_uzi_cd <= 0;

            //p2 uzi
            if (p2_weapon == WEAPON_UZI && p2_fire_pressed && p2_alive) begin
                if (p2_uzi_cd == 0) begin p2_uzi_fire <= 1; p2_uzi_cd <= 4'd5; end 
                else p2_uzi_cd <= p2_uzi_cd - 1;
            end else p2_uzi_cd <= 0;
        end
    end

    //per-bullet velocity and lifetime state
    logic signed [5:0] bullet_vx [20];
    logic signed [5:0] bullet_vy [20];
    logic [7:0]        bullet_life [20];

    function automatic void get_spawn_pos(input logic [2:0] dir, input logic [10:0] px, input logic [10:0] py, output logic [10:0] bx, output logic [10:0] by);
        case (dir)
            3'd0: begin bx = px + 7;  by = py + 16; end 
            3'd1: begin bx = px + 7;  by = py;      end 
            3'd2: begin bx = px;      by = py + 7;  end 
            3'd3: begin bx = px + 16; by = py + 7;  end 
            3'd4: begin bx = px;      by = py + 16; end 
            3'd5: begin bx = px + 16; by = py + 16; end 
            3'd6: begin bx = px;      by = py;      end 
            3'd7: begin bx = px + 16; by = py;      end 
            default: begin bx = px + 7; by = py + 7; end 
        endcase
    endfunction

    function automatic void get_vector(input logic [2:0] dir, input logic [2:0] spread_id, input logic [1:0] weapon, output logic signed [5:0] vx, output logic signed [5:0] vy);
        int base_v; base_v = (weapon == WEAPON_UZI) ? 9 : 7; 
        vx = 0; vy = 0;
        case (dir)
            3'd0: case(spread_id) 0:begin vx=0;vy=base_v;end 1:begin vx=-2;vy=base_v-1;end 2:begin vx=2;vy=base_v-1;end 3:begin vx=-4;vy=base_v-2;end 4:begin vx=4;vy=base_v-2;end default:begin vx=0;vy=base_v;end endcase
            3'd1: case(spread_id) 0:begin vx=0;vy=-base_v;end 1:begin vx=-2;vy=-(base_v-1);end 2:begin vx=2;vy=-(base_v-1);end 3:begin vx=-4;vy=-(base_v-2);end 4:begin vx=4;vy=-(base_v-2);end default:begin vx=0;vy=-base_v;end endcase
            3'd2: case(spread_id) 0:begin vx=-base_v;vy=0;end 1:begin vx=-(base_v-1);vy=-2;end 2:begin vx=-(base_v-1);vy=2;end 3:begin vx=-(base_v-2);vy=-4;end 4:begin vx=-(base_v-2);vy=4;end default:begin vx=-base_v;vy=0;end endcase
            3'd3: case(spread_id) 0:begin vx=base_v;vy=0;end 1:begin vx=base_v-1;vy=-2;end 2:begin vx=base_v-1;vy=2;end 3:begin vx=base_v-2;vy=-4;end 4:begin vx=base_v-2;vy=4;end default:begin vx=base_v;vy=0;end endcase
            3'd4: case(spread_id) 0:begin vx=-5;vy=5;end 1:begin vx=-3;vy=7;end 2:begin vx=-7;vy=3;end 3:begin vx=-1;vy=9;end 4:begin vx=-9;vy=1;end default:begin vx=-5;vy=5;end endcase 
            3'd5: case(spread_id) 0:begin vx=5;vy=5;end 1:begin vx=7;vy=3;end 2:begin vx=3;vy=7;end 3:begin vx=9;vy=1;end 4:begin vx=1;vy=9;end default:begin vx=5;vy=5;end endcase 
            3'd6: case(spread_id) 0:begin vx=-5;vy=-5;end 1:begin vx=-3;vy=-7;end 2:begin vx=-7;vy=-3;end 3:begin vx=-1;vy=-9;end 4:begin vx=-9;vy=-1;end default:begin vx=-5;vy=-5;end endcase 
            3'd7: case(spread_id) 0:begin vx=5;vy=-5;end 1:begin vx=7;vy=-3;end 2:begin vx=3;vy=-7;end 3:begin vx=9;vy=-1;end 4:begin vx=1;vy=-9;end default:begin vx=5;vy=-5;end endcase 
        endcase
    endfunction

    //bullet movement, cleanup, and spawning
    always_ff @(posedge Clk) begin
        if (Reset) begin
            bullet_active <= 20'b0;
            shoot_pulse_r <= 1'b0;
        end else if (frame_tick) begin
            shoot_pulse_r <= 1'b0;
            
            //update active bullets and remove expired or blocked shots
            for (int i = 0; i < 20; i++) begin
                if (bullet_active[i]) begin
                    if (bullet_destroy_mask[i]) begin
                        bullet_active[i] <= 1'b0; 
                    end else begin
                        bullet_x[i] <= bullet_x[i] + {{5{bullet_vx[i][5]}}, bullet_vx[i]};
                        bullet_y[i] <= bullet_y[i] + {{5{bullet_vy[i][5]}}, bullet_vy[i]};
                        bullet_life[i] <= bullet_life[i] - 1;

                        if (bullet_life[i] == 0 || 
                            bullet_x[i] <= 6 || bullet_x[i] >= MAX_X - 6 || 
                            bullet_y[i] <= 6 || bullet_y[i] >= MAX_Y - 6 ||
                            is_obstacle(bullet_x[i], bullet_y[i])) begin
                            bullet_active[i] <= 1'b0; 
                        end
                    end
                end
            end

            //player 1 firing logic uses slots 0-9
            if (p1_alive) begin
                int p1_spawn_count; 
                p1_spawn_count = 0;

                //revolver: single shot
                if (p1_weapon == WEAPON_REV && p1_fire_edge) begin
                    logic p1_spawned;
                    p1_spawned = 1'b0;
                    shoot_pulse_r <= 1'b1;
                    for (int j = 0; j < 10; j++) begin
                        if (!bullet_active[j] && !p1_spawned) begin
                            bullet_active[j] <= 1'b1; bullet_life[j] <= 8'd100;
                            get_spawn_pos(p1_dir, p1_x, p1_y, bullet_x[j], bullet_y[j]);
                            get_vector(p1_dir, 3'd0, WEAPON_REV, bullet_vx[j], bullet_vy[j]);
                            p1_spawned = 1'b1;
                        end
                    end
                end
                //uzi: automatic single shots
                else if (p1_weapon == WEAPON_UZI && p1_uzi_fire) begin
                    logic p1_spawned;
                    p1_spawned = 1'b0;
                    shoot_pulse_r <= 1'b1;
                    for (int j = 0; j < 10; j++) begin
                        if (!bullet_active[j] && !p1_spawned) begin
                            bullet_active[j] <= 1'b1; bullet_life[j] <= 8'd60;
                            get_spawn_pos(p1_dir, p1_x, p1_y, bullet_x[j], bullet_y[j]);
                            get_vector(p1_dir, 3'd0, WEAPON_UZI, bullet_vx[j], bullet_vy[j]);
                            p1_spawned = 1'b1;
                        end
                    end
                end
                //shotgun: five-pellet burst
                else if (p1_weapon == WEAPON_SHOT && p1_fire_edge) begin
                    shoot_pulse_r <= 1'b1;
                    for (int j = 0; j < 10; j++) begin
                        if (!bullet_active[j] && p1_spawn_count < 5) begin
                            bullet_active[j] <= 1'b1; bullet_life[j] <= 8'd12;
                            get_spawn_pos(p1_dir, p1_x, p1_y, bullet_x[j], bullet_y[j]);
                            get_vector(p1_dir, p1_spawn_count[2:0], WEAPON_SHOT, bullet_vx[j], bullet_vy[j]);
                            p1_spawn_count = p1_spawn_count + 1;
                        end
                    end
                end
            end

            //player 2 firing logic uses slots 10-19
            if (p2_alive) begin
                int p2_spawn_count; 
                p2_spawn_count = 0;

                //revolver: single shot
                if (p2_weapon == WEAPON_REV && p2_fire_edge) begin
                    logic p2_spawned;
                    p2_spawned = 1'b0;
                    shoot_pulse_r <= 1'b1;
                    for (int k = 10; k < 20; k++) begin
                        if (!bullet_active[k] && !p2_spawned) begin
                            bullet_active[k] <= 1'b1; bullet_life[k] <= 8'd100;
                            get_spawn_pos(p2_dir, p2_x, p2_y, bullet_x[k], bullet_y[k]);
                            get_vector(p2_dir, 3'd0, WEAPON_REV, bullet_vx[k], bullet_vy[k]);
                            p2_spawned = 1'b1;
                        end
                    end
                end
                //uzi: automatic single shots
                else if (p2_weapon == WEAPON_UZI && p2_uzi_fire) begin
                    logic p2_spawned;
                    p2_spawned = 1'b0;
                    shoot_pulse_r <= 1'b1;
                    for (int k = 10; k < 20; k++) begin
                        if (!bullet_active[k] && !p2_spawned) begin
                            bullet_active[k] <= 1'b1; bullet_life[k] <= 8'd60;
                            get_spawn_pos(p2_dir, p2_x, p2_y, bullet_x[k], bullet_y[k]);
                            get_vector(p2_dir, 3'd0, WEAPON_UZI, bullet_vx[k], bullet_vy[k]);
                            p2_spawned = 1'b1;
                        end
                    end
                end
                //shotgun: five-pellet burst
                else if (p2_weapon == WEAPON_SHOT && p2_fire_edge) begin
                    shoot_pulse_r <= 1'b1;
                    for (int k = 10; k < 20; k++) begin
                        if (!bullet_active[k] && p2_spawn_count < 5) begin
                            bullet_active[k] <= 1'b1; bullet_life[k] <= 8'd12; 
                            get_spawn_pos(p2_dir, p2_x, p2_y, bullet_x[k], bullet_y[k]);
                            get_vector(p2_dir, p2_spawn_count[2:0], WEAPON_SHOT, bullet_vx[k], bullet_vy[k]);
                            p2_spawn_count = p2_spawn_count + 1;
                        end
                    end
                end
            end
        end
    end
    
    //obstacle lookup in 16x16 map tiles
    function automatic logic is_obstacle(input [10:0] x, input [10:0] y);
        logic [6:0] tx, ty;
        tx = x[10:4];
        ty = y[10:4];
        
        //map boundary is treated as solid
        if (ty < 2 || ty >= 126 || tx < 1 || tx >= 127) begin
            return 1'b1;
        end

        //static obstacle layout mirrored from the tile map
        //upper obstacle row (ty: 25-28)
        if (ty >= 25 && ty <= 28) begin
            if (tx >= 25 && tx <= 27) return 1'b1;
            if (tx >= 29 && tx <= 31 && ty >= 27) return 1'b1; 
            if (tx >= 33 && tx <= 35 && ty >= 26) return 1'b1; 
            if (tx >= 37 && tx <= 39) return 1'b1; 
            if (tx >= 40 && tx <= 42 && ty <= 27) return 1'b1; 
            if (tx >= 55 && tx <= 57 && ty <= 26) return 1'b1; 
            if (tx >= 65 && tx <= 67 && ty <= 27) return 1'b1; 
            if (tx >= 72 && tx <= 74) return 1'b1; 
        end
        
        //middle obstacle row (ty: 55-58)
        if (ty >= 55 && ty <= 58) begin
            if (tx >= 25 && tx <= 27) return 1'b1; 
            if (tx >= 30 && tx <= 32 && ty >= 65 && ty <= 66) return 1'b1; //unreachable with the current ty range; kept as-is
            if (tx >= 40 && tx <= 42 && ty <= 57) return 1'b1; 
            if (tx >= 55 && tx <= 57) return 1'b1; 
            if (tx >= 59 && tx <= 61 && ty >= 57) return 1'b1; 
            if (tx >= 63 && tx <= 65 && ty >= 56) return 1'b1; 
            if (tx >= 67 && tx <= 69) return 1'b1; 
            if (tx >= 72 && tx <= 74 && ty <= 56) return 1'b1; 
        end
        
        //lower obstacle row (ty: 85-88)
        if (ty >= 85 && ty <= 88) begin
            if (tx >= 25 && tx <= 27) return 1'b1; 
            if (tx >= 29 && tx <= 31 && ty >= 87) return 1'b1; 
            if (tx >= 33 && tx <= 35 && ty >= 86) return 1'b1; 
            if (tx >= 37 && tx <= 39) return 1'b1; 
            if (tx >= 55 && tx <= 57 && ty <= 87) return 1'b1; 
            if (tx >= 60 && tx <= 62 && ty <= 87) return 1'b1; 
            if (tx >= 65 && tx <= 67) return 1'b1; 
        end

        //no obstacle at this tile
        return 1'b0;
    endfunction

    //check all four corners of a 16x16 entity
    function automatic logic check_entity_collision(input [10:0] x, input [10:0] y);
        return is_obstacle(x, y) |
               is_obstacle(x+15, y) |
               is_obstacle(x, y+15) |
               is_obstacle(x+15, y+15);
    endfunction
endmodule
