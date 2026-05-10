module zombie_controller (
    input  logic        Clk,
    input  logic        Reset,
    input  logic        vsync_in,
    
    //spawn request
    input  logic        spawn_en,      
    input  logic [10:0] spawn_x,       
    input  logic [10:0] spawn_y,       
    
    //player positions and health
    input  logic [10:0] p1_x,
    input  logic [10:0] p1_y,
    input  logic [3:0]  p1_hp,
    
    input  logic [10:0] p2_x,
    input  logic [10:0] p2_y,
    input  logic [3:0]  p2_hp,

    //bullet state from bullet_controller
    input  logic [10:0] bullet_x [20],
    input  logic [10:0] bullet_y [20],
    input  logic [19:0] bullet_active,
    
    //zombie state and collision feedback
    output logic [10:0] zombie_x,
    output logic [10:0] zombie_y,
    output logic        zombie_is_alive,
    output logic [2:0]  zombie_hp,            
    output logic [19:0] bullet_destroy_mask, //one-shot mask for bullets that hit this zombie
    
    output logic        p1_damage_flag,
    output logic        p2_damage_flag,

    output logic        zombie_hit_pulse
);

    parameter [10:0] ZOMBIE_SPEED = 11'd1; 

    logic vsync_prev, frame_tick;
    always_ff @(posedge Clk) vsync_prev <= vsync_in;
    assign frame_tick = (vsync_prev == 1'b1 && vsync_in == 1'b0);

    logic zombie_hit_pulse_r;
    assign zombie_hit_pulse = zombie_hit_pulse_r;

    logic [10:0] next_x, next_y;
    logic [19:0] current_hits;
    logic [1:0]  move_counter;
    
    //move only every third frame to slow the zombie down
    always_ff @(posedge Clk) begin
        if (Reset)
            move_counter <= 0;
        else if (frame_tick)
            move_counter <= (move_counter == 2) ? 0 : move_counter + 1;
    end

    //target selection helper
    function automatic logic [11:0] abs_diff(input [10:0] a, input [10:0] b);
        return (a > b) ? (a - b) : (b - a);
    endfunction

    logic [11:0] dist_p1, dist_p2;
    logic        target_is_p2;
    logic [10:0] target_x, target_y;

    always_comb begin
        //measure distance to each alive player; dead players are ignored
        dist_p1 = (p1_hp > 0) ? (abs_diff(p1_x, zombie_x) + abs_diff(p1_y, zombie_y)) : 12'hFFF;
        dist_p2 = (p2_hp > 0) ? (abs_diff(p2_x, zombie_x) + abs_diff(p2_y, zombie_y)) : 12'hFFF;
        
        //chase the closest alive player
        target_is_p2 = (dist_p2 < dist_p1); 
        target_x = target_is_p2 ? p2_x : p1_x;
        target_y = target_is_p2 ? p2_y : p1_y;
    end
    
    //zombie lifecycle and collision handling
    always_ff @(posedge Clk) begin
        if (Reset) begin
            zombie_hit_pulse_r <= 1'b0;
            zombie_is_alive <= 1'b0;
            zombie_hp <= 3'd0;
            bullet_destroy_mask <= 20'b0;
            p1_damage_flag <= 1'b0;
            p2_damage_flag <= 1'b0;
        end 
        
        //spawn at the requested location
        else if (spawn_en) begin
            zombie_is_alive <= 1'b1;
            zombie_hp <= 3'd5; 
            zombie_x <= spawn_x;
            zombie_y <= spawn_y;
        end
        
        //update movement, bullet hits, and player contact once per frame
        else if (frame_tick && zombie_is_alive) begin
            zombie_hit_pulse_r <= 1'b0;
            
            //move toward the current target when not blocked
            if (move_counter != 2) begin
                next_x = zombie_x; 
                next_y = zombie_y;

                if (zombie_x < target_x) next_x = zombie_x + ZOMBIE_SPEED;
                if (zombie_x > target_x) next_x = zombie_x - ZOMBIE_SPEED;
                if (zombie_y < target_y) next_y = zombie_y + ZOMBIE_SPEED;
                if (zombie_y > target_y) next_y = zombie_y - ZOMBIE_SPEED;

                if (!check_entity_collision(next_x, zombie_y)) zombie_x <= next_x;
                if (!check_entity_collision(zombie_x, next_y)) zombie_y <= next_y;
            end

            //mark bullets overlapping the zombie hit box
            current_hits = 20'b0;
            for (int i = 0; i < 20; i++) begin
                if (bullet_active[i] && 
                    bullet_x[i] >= zombie_x && bullet_x[i] < zombie_x + 16 &&
                    bullet_y[i] >= zombie_y && bullet_y[i] < zombie_y + 16) begin
                    current_hits[i] = 1'b1; 
                end
            end
            bullet_destroy_mask <= current_hits; 
            
            //apply one damage point for any bullet hit
            if (current_hits != 0) begin
                zombie_hit_pulse_r <= 1'b1;
                if (zombie_hp > 1) begin
                    zombie_hp <= zombie_hp - 1'b1;
                end else begin
                    zombie_hp <= 3'd0;
                    zombie_is_alive <= 1'b0; //dead after the last hit
                end
            end

            //raise damage flags while overlapping either alive player
            if (p1_hp > 0 && p1_x < zombie_x + 16 && p1_x + 16 > zombie_x &&
                p1_y < zombie_y + 16 && p1_y + 16 > zombie_y) begin
                p1_damage_flag <= 1'b1;
            end else begin
                p1_damage_flag <= 1'b0;
            end

            if (p2_hp > 0 && p2_x < zombie_x + 16 && p2_x + 16 > zombie_x &&
                p2_y < zombie_y + 16 && p2_y + 16 > zombie_y) begin
                p2_damage_flag <= 1'b1;
            end else begin
                p2_damage_flag <= 1'b0;
            end

        end 
        
        //clear pulses while inactive
        else if (frame_tick && !zombie_is_alive) begin
            bullet_destroy_mask <= 20'b0;
            p1_damage_flag <= 1'b0;
            p2_damage_flag <= 1'b0;
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
