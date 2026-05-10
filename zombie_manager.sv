module zombie_manager (
    input  logic        Clk,
    input  logic        Reset,
    input  logic        vsync_in,
    
    //player positions and health
    input  logic [10:0] p1_x,
    input  logic [10:0] p1_y,
    input  logic [3:0]  p1_hp,
    
    input  logic [10:0] p2_x,
    input  logic [10:0] p2_y,
    input  logic [3:0]  p2_hp,

    //bullets from bullet_controller
    input  logic [10:0] bullet_x [20],
    input  logic [10:0] bullet_y [20],
    input  logic [19:0]  bullet_active,

    //zombie arrays sent to rendering and gameplay systems
    output logic [10:0] zombie_x [10],
    output logic [10:0] zombie_y [10],
    output logic [9:0]  zombie_is_alive,
    output logic [2:0]  zombie_hp [10],   
    
    //aggregated collision outputs
    output logic [19:0]  total_bullet_destroy_mask,
    output logic        total_p1_damage_flag,
    output logic        total_p2_damage_flag
);

    logic vsync_prev, frame_tick;
    always_ff @(posedge Clk) vsync_prev <= vsync_in;
    assign frame_tick = (vsync_prev == 1'b1 && vsync_in == 1'b0);

    //pseudo-random spawn source
    logic [21:0] random_val;
    always_ff @(posedge Clk) begin
        if (Reset) random_val <= 22'h3FFFFF;
        else random_val <= {random_val[20:0], random_val[21] ^ random_val[20]};
    end

    //clamp spawn coordinates to the playable area
    logic [10:0] rand_x, rand_y;
    always_comb begin
        rand_x = random_val[10:0];
        rand_y = random_val[21:11];
        if (rand_x < 128) rand_x = 128;
        if (rand_x > 1900) rand_x = 1900;
        if (rand_y < 128) rand_y = 128;
        if (rand_y > 1900) rand_y = 1900;
    end

    //spawn scheduler
    logic [7:0] spawn_timer;
    logic [9:0] spawn_en_array;

    always_ff @(posedge Clk) begin
        if (Reset) begin
            spawn_timer <= 0;
            spawn_en_array <= 0;
        end else if (frame_tick) begin
            spawn_en_array <= 0;
            
            if (spawn_timer == 8'd120) begin
                spawn_timer <= 0;
                //find the first inactive zombie slot
                for (int i = 0; i < 10; i++) begin
                    if (!zombie_is_alive[i]) begin
                        spawn_en_array[i] <= 1; 
                        break;
                    end
                end
            end else begin
                spawn_timer <= spawn_timer + 1;
            end
        end
    end

    //per-zombie feedback wires
    logic [9:0] individual_bullet_masks [10];
    logic [9:0] individual_p1_damage_flags;
    logic [9:0] individual_p2_damage_flags;

    //instantiate ten zombie controllers
    genvar i;
    generate
        for (i = 0; i < 10; i++) begin : zombies
            //one controller owns one zombie slot
            zombie_controller z_inst (
                .Clk(Clk),
                .Reset(Reset),
                .vsync_in(vsync_in),
                
                .spawn_en(spawn_en_array[i]),
                .spawn_x(rand_x),
                .spawn_y(rand_y),
                
                //shared player state
                .p1_x(p1_x),
                .p1_y(p1_y),
                .p1_hp(p1_hp),
                
                .p2_x(p2_x),
                .p2_y(p2_y),
                .p2_hp(p2_hp),
                
                .bullet_x(bullet_x),
                .bullet_y(bullet_y),
                .bullet_active(bullet_active),
                
                //per-zombie state outputs
                .zombie_x(zombie_x[i]),
                .zombie_y(zombie_y[i]),
                .zombie_is_alive(zombie_is_alive[i]),  
                .zombie_hp(zombie_hp[i]),              
                .bullet_destroy_mask(individual_bullet_masks[i]),
                
                //damage flags for either player
                .p1_damage_flag(individual_p1_damage_flags[i]),
                .p2_damage_flag(individual_p2_damage_flags[i])
            );
        end
    endgenerate

    //combine all per-zombie masks and flags
    always_comb begin
        total_bullet_destroy_mask = 0;
        total_p1_damage_flag  = 0;
        total_p2_damage_flag  = 0;
        for (int j = 0; j < 10; j++) begin
            total_bullet_destroy_mask |= individual_bullet_masks[j];
            total_p1_damage_flag      |= individual_p1_damage_flags[j];
            total_p2_damage_flag      |= individual_p2_damage_flags[j];
        end
    end

endmodule
