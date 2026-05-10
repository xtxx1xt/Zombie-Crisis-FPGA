module pickup_manager (
    input  logic        Clk,
    input  logic        Reset,
    input  logic        vsync_in,
    
    input  logic [10:0] zombie_x [10],
    input  logic [10:0] zombie_y [10],
    input  logic [9:0]  zombie_is_alive,
    
    input  logic [10:0] p1_x, p1_y,
    input  logic [10:0] p2_x, p2_y,
    input  logic [3:0]  p1_hp, p2_hp,
    
    output logic [10:0] pickup_x [5],
    output logic [10:0] pickup_y [5],
    output logic [4:0]  pickup_active,
    
    output logic p1_heal_pulse,
    output logic p2_heal_pulse
);

    logic vsync_prev, frame_tick;
    always_ff @(posedge Clk) vsync_prev <= vsync_in;
    assign frame_tick = (vsync_prev == 1'b1 && vsync_in == 1'b0);

    logic [9:0] zombie_alive_prev;
    logic p1_hit, p2_hit;

    always_ff @(posedge Clk) begin
        if (Reset) begin
            zombie_alive_prev <= 10'b0;
            pickup_active <= 5'b0;
            p1_heal_pulse <= 1'b0;
            p2_heal_pulse <= 1'b0;
        end else if (frame_tick) begin
            p1_heal_pulse <= 1'b0;
            p2_heal_pulse <= 1'b0;
            zombie_alive_prev <= zombie_is_alive;
            
            //check active pickups for player overlap
            for (int i = 0; i < 5; i++) begin
                if (pickup_active[i]) begin

                    p1_hit = (p1_x + 16 > pickup_x[i] && p1_x < pickup_x[i] + 16 &&
                            p1_y + 16 > pickup_y[i] && p1_y < pickup_y[i] + 16);

                    p2_hit = (p2_x + 16 > pickup_x[i] && p2_x < pickup_x[i] + 16 &&
                            p2_y + 16 > pickup_y[i] && p2_y < pickup_y[i] + 16);

                    if ((p1_hit && p1_hp > 0) || (p2_hit && p2_hp > 0)) begin
                        pickup_active[i] <= 1'b0;
                        if (p1_hit && p1_hp > 0) p1_heal_pulse <= 1'b1;
                        if (p2_hit && p2_hp > 0) p2_heal_pulse <= 1'b1;
                    end

                end
            end

            //spawn pickups when zombies die
            for (int z = 0; z < 10; z++) begin
                //detect a zombie death edge
                if (zombie_alive_prev[z] == 1'b1 && zombie_is_alive[z] == 1'b0) begin
                    
                    //use low position bits as a simple 25 percent drop chance
                    if ((zombie_x[z][2:1] ^ zombie_y[z][2:1]) == 2'b00) begin
                        
                        //put the pickup in the first free slot
                        if (!pickup_active[0]) begin
                            pickup_active[0] <= 1'b1; pickup_x[0] <= zombie_x[z]; pickup_y[0] <= zombie_y[z];
                        end else if (!pickup_active[1]) begin
                            pickup_active[1] <= 1'b1; pickup_x[1] <= zombie_x[z]; pickup_y[1] <= zombie_y[z];
                        end else if (!pickup_active[2]) begin
                            pickup_active[2] <= 1'b1; pickup_x[2] <= zombie_x[z]; pickup_y[2] <= zombie_y[z];
                        end else if (!pickup_active[3]) begin
                            pickup_active[3] <= 1'b1; pickup_x[3] <= zombie_x[z]; pickup_y[3] <= zombie_y[z];
                        end else if (!pickup_active[4]) begin
                            pickup_active[4] <= 1'b1; pickup_x[4] <= zombie_x[z]; pickup_y[4] <= zombie_y[z];
                        end
                        
                    end
                end
            end
        end
    end
endmodule
