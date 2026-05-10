module player_controller (
    input  logic        Clk,       
    input  logic        Reset,
    input  logic        vsync_in,  
    input  logic [31:0] keycode,   
    
    //damage, healing, and hp outputs for both players
    input  logic        p1_damage_flag,
    input  logic        p2_damage_flag,
    input  logic        p1_heal_pulse,
    input  logic        p2_heal_pulse,

    output logic [3:0]  p1_hp,
    output logic [3:0]  p2_hp,
    output logic        player_hit_pulse,

    //player position, camera, and facing outputs
    output logic [10:0] p1_x, p1_y,
    output logic [10:0] p2_x, p2_y,

    output logic [10:0] camera_x,  
    output logic [10:0] camera_y,  

    output logic [2:0]  p1_dir,
    output logic [2:0]  p2_dir,

    //weapon inventory and world drops
    output logic [1:0]  p1_weapon,         //0=revolver, 1=shotgun, 2=uzi
    output logic [1:0]  p2_weapon,
    
    output logic [10:0] weapon_drop_x [4], //x position for each weapon drop
    output logic [10:0] weapon_drop_y [4], //y position for each weapon drop
    output logic [1:0]  weapon_drop_type [4], //weapon type for each drop
    output logic [3:0]  weapon_drop_active //active drop bitmask
);

    logic p1_alive, p2_alive;

    assign p1_alive = (p1_hp > 0);
    assign p2_alive = (p2_hp > 0);

    logic player_hit_pulse_r;
    assign player_hit_pulse = player_hit_pulse_r;

    parameter [10:0] STEP = 11'd2;     
    localparam MAP_W = 2048;
    localparam MAP_H = 2048;

    localparam LOGICAL_W = 320; 
    localparam LOGICAL_H = 240; 
    
    localparam MAX_HP = 4'd10;

    //frame tick
    logic vsync_prev, frame_tick;

    always_ff @(posedge Clk) begin
        vsync_prev <= vsync_in;
    end

    assign frame_tick = (vsync_prev && !vsync_in);

    //keyboard bitmask decode
    logic W_on, A_on, S_on, D_on;
    logic I_on, J_on, K_on, L_on;

    //player 1 (bit 0~3)
    assign W_on = keycode[0];
    assign S_on = keycode[1];
    assign A_on = keycode[2];
    assign D_on = keycode[3];

    //player 2 (bit 8~11)
    assign I_on = keycode[8];
    assign K_on = keycode[9];
    assign J_on = keycode[10];
    assign L_on = keycode[11];

    //camera follows the midpoint of the living players
    always_comb begin
        int mid_x;
        int mid_y;
        int ideal_cam_x;
        int ideal_cam_y;

        if (p1_alive && p2_alive) begin
            mid_x = (p1_x + p2_x) / 2;
            mid_y = (p1_y + p2_y) / 2;
        end
        else if (p1_alive) begin
            mid_x = p1_x;
            mid_y = p1_y;
        end
        else begin
            mid_x = p2_x;
            mid_y = p2_y;
        end

        ideal_cam_x = mid_x + 8 - (LOGICAL_W / 2);
        ideal_cam_y = mid_y + 8 - (LOGICAL_H / 2);

        if (ideal_cam_x < 0) camera_x = 0;
        else if (ideal_cam_x > MAP_W - LOGICAL_W) camera_x = MAP_W - LOGICAL_W;
        else camera_x = ideal_cam_x[10:0];

        if (ideal_cam_y < 0) camera_y = 0;
        else if (ideal_cam_y > MAP_H - LOGICAL_H) camera_y = MAP_H - LOGICAL_H;
        else camera_y = ideal_cam_y[10:0];
    end

    //candidate movement positions
    logic [10:0] p1_next_x, p1_next_y;
    logic [10:0] p2_next_x, p2_next_y;

    always_comb begin
        p1_next_x = p1_x;
        p1_next_y = p1_y;

        if (p1_alive && W_on && p1_y > 0) p1_next_y = p1_y - STEP;
        if (p1_alive && S_on && p1_y < MAP_H - 16) p1_next_y = p1_y + STEP;
        if (p1_alive && A_on && p1_x > 0) p1_next_x = p1_x - STEP;
        if (p1_alive && D_on && p1_x < MAP_W - 16) p1_next_x = p1_x + STEP;

        if (p1_next_x < camera_x) p1_next_x = camera_x;
        if (p1_next_x > camera_x + LOGICAL_W - 16) p1_next_x = camera_x + LOGICAL_W - 16;
        if (p1_next_y < camera_y) p1_next_y = camera_y;
        if (p1_next_y > camera_y + LOGICAL_H - 16) p1_next_y = camera_y + LOGICAL_H - 16;
    end

    always_comb begin
        p2_next_x = p2_x;
        p2_next_y = p2_y;

        if (p2_alive && I_on && p2_y > 0) p2_next_y = p2_y - STEP;
        if (p2_alive && K_on && p2_y < MAP_H - 16) p2_next_y = p2_y + STEP;
        if (p2_alive && J_on && p2_x > 0) p2_next_x = p2_x - STEP;
        if (p2_alive && L_on && p2_x < MAP_W - 16) p2_next_x = p2_x + STEP;

        if (p2_next_x < camera_x) p2_next_x = camera_x;
        if (p2_next_x > camera_x + LOGICAL_W - 16) p2_next_x = camera_x + LOGICAL_W - 16;
        if (p2_next_y < camera_y) p2_next_y = camera_y;
        if (p2_next_y > camera_y + LOGICAL_H - 16) p2_next_y = camera_y + LOGICAL_H - 16;
    end

    //invincibility cooldowns after taking damage
    logic [5:0] p1_inv, p2_inv;

    //player state update
    always_ff @(posedge Clk) begin
        if (Reset) begin
            player_hit_pulse_r <= 1'b0;
            p1_x <= 11'd1024;
            p1_y <= 11'd1024;
            p2_x <= 11'd1050;
            p2_y <= 11'd1050;

            p1_hp <= MAX_HP;
            p2_hp <= MAX_HP;
            p1_inv <= 0;
            p2_inv <= 0;

            p1_dir <= 3'd0; 
            p2_dir <= 3'd0; 

            //start both players with revolvers
            p1_weapon <= 2'd0; //revolver
            p2_weapon <= 2'd0; //revolver

            //place initial weapon drops in the world
            weapon_drop_x[0] <= 11'd320; weapon_drop_y[0] <= 11'd320; weapon_drop_type[0] <= 2'd1; weapon_drop_active[0] <= 1'b1; //shotgun
            weapon_drop_x[1] <= 11'd800; weapon_drop_y[1] <= 11'd320; weapon_drop_type[1] <= 2'd2; weapon_drop_active[1] <= 1'b1; //uzi
            weapon_drop_x[2] <= 11'd320; weapon_drop_y[2] <= 11'd800; weapon_drop_type[2] <= 2'd1; weapon_drop_active[2] <= 1'b1; //shotgun
            weapon_drop_x[3] <= 11'd800; weapon_drop_y[3] <= 11'd800; weapon_drop_type[3] <= 2'd2; weapon_drop_active[3] <= 1'b1; //uzi

        end else if (frame_tick) begin
            player_hit_pulse_r <= 1'b0;

            //update player 1 position and facing
            if (!check_entity_collision(p1_next_x, p1_y)) p1_x <= p1_next_x;
            if (!check_entity_collision(p1_x, p1_next_y)) p1_y <= p1_next_y;

            if (p1_alive && W_on && A_on) p1_dir <= 3'd6; 
            else if (p1_alive && W_on && D_on) p1_dir <= 3'd7; 
            else if (p1_alive && S_on && A_on) p1_dir <= 3'd4; 
            else if (p1_alive && S_on && D_on) p1_dir <= 3'd5; 
            else if (p1_alive && W_on) p1_dir <= 3'd1; 
            else if (p1_alive && S_on) p1_dir <= 3'd0; 
            else if (p1_alive && A_on) p1_dir <= 3'd2; 
            else if (p1_alive && D_on) p1_dir <= 3'd3; 

            //apply player 1 damage and healing
            if (p1_inv > 0) p1_inv <= p1_inv - 1;
            if (p1_damage_flag && p1_inv == 0 && p1_hp > 0) begin
                player_hit_pulse_r <= 1'b1;
                p1_hp <= p1_hp - 1;
                p1_inv <= 60;
            end
            if (p1_heal_pulse && p1_hp < MAX_HP && p1_hp > 0)
                p1_hp <= p1_hp + 1;

            //update player 2 position and facing
            if (!check_entity_collision(p2_next_x, p2_y)) p2_x <= p2_next_x;
            if (!check_entity_collision(p2_x, p2_next_y)) p2_y <= p2_next_y;

            if (p2_alive && I_on && J_on) p2_dir <= 3'd6; 
            else if (p2_alive && I_on && L_on) p2_dir <= 3'd7; 
            else if (p2_alive && K_on && J_on) p2_dir <= 3'd4; 
            else if (p2_alive && K_on && L_on) p2_dir <= 3'd5; 
            else if (p2_alive && I_on) p2_dir <= 3'd1; 
            else if (p2_alive && K_on) p2_dir <= 3'd0; 
            else if (p2_alive && J_on) p2_dir <= 3'd2; 
            else if (p2_alive && L_on) p2_dir <= 3'd3; 

            //apply player 2 damage and healing
            if (p2_inv > 0) p2_inv <= p2_inv - 1;
            if (p2_damage_flag && p2_inv == 0 && p2_hp > 0) begin
                player_hit_pulse_r <= 1'b1;
                p2_hp <= p2_hp - 1;
                p2_inv <= 60;
            end
            if (p2_heal_pulse && p2_hp < MAX_HP && p2_hp > 0)
                p2_hp <= p2_hp + 1;
            
            //pick up weapon drops on overlap
            for (int i = 0; i < 4; i++) begin
                if (weapon_drop_active[i]) begin
                    //player 1 picks up this weapon
                    if (p1_alive && 
                        p1_x < weapon_drop_x[i] + 16 && p1_x + 16 > weapon_drop_x[i] &&
                        p1_y < weapon_drop_y[i] + 16 && p1_y + 16 > weapon_drop_y[i]) begin
                        p1_weapon <= weapon_drop_type[i];
                        weapon_drop_active[i] <= 1'b0; //remove the drop once taken
                    end
                    //player 2 picks up this weapon
                    else if (p2_alive && 
                             p2_x < weapon_drop_x[i] + 16 && p2_x + 16 > weapon_drop_x[i] &&
                             p2_y < weapon_drop_y[i] + 16 && p2_y + 16 > weapon_drop_y[i]) begin
                        p2_weapon <= weapon_drop_type[i];
                        weapon_drop_active[i] <= 1'b0; 
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
