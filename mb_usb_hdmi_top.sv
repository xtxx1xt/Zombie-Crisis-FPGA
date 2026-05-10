//mb_usb_hdmi_top.sv
//zuofu Cheng
//2-29-24
//10-14-25
//fall 2025 distribution
//for use with ece 385 usb + hdmi
//university of Illinois ece department

module mb_usb_hdmi_top(
    input logic Clk,
    input logic reset_rtl_0,
    
    //usb signals
    input logic [0:0] gpio_usb_int_tri_i,
    output logic gpio_usb_rst_tri_o,
    input logic usb_spi_miso,
    output logic usb_spi_mosi,
    output logic usb_spi_sclk,
    output logic usb_spi_ss,
    
    //uart
    input logic uart_rtl_0_rxd,
    output logic uart_rtl_0_txd,
    
    //hdmi
    output logic hdmi_tmds_clk_n,
    output logic hdmi_tmds_clk_p,
    output logic [2:0]hdmi_tmds_data_n,
    output logic [2:0]hdmi_tmds_data_p,
        
    //hex displays
    output logic [7:0] hex_segA,
    output logic [3:0] hex_gridA,
    output logic [7:0] hex_segB,
    output logic [3:0] hex_gridB,
    output logic SPKL,
    output logic SPKR

);
    
    logic [31:0] keycode0_gpio, keycode1_gpio;
    logic clk_25MHz, clk_125MHz, clk, clk_100MHz;
    logic locked;
    logic [9:0] drawX, drawY;

    //game state signals
    logic [10:0] p1_x, p1_y;
    logic [10:0] p2_x, p2_y;
    logic [2:0]  p1_dir, p2_dir;
    logic [3:0]  p1_hp, p2_hp;
    
    logic total_p1_damage_flag;
    logic total_p2_damage_flag;

    logic [10:0] camera_x, camera_y;

    logic [10:0] zombie_x_array [10];
    logic [10:0] zombie_y_array [10];
    logic [10:0] bullet_x_array [20];
    logic [10:0] bullet_y_array [20];
    logic hsync, vsync, vde;
    logic [3:0] red, green, blue;
    logic reset_ah;
    logic [10:0] pickup_x_array [5];
    logic [10:0] pickup_y_array [5];
    logic [4:0]  pickup_active_mask;
    logic p1_heal_pulse;
    logic p2_heal_pulse;
    
    logic [7:0] kill_count;
    logic [9:0] zombie_alive_prev;
    logic [9:0] death_pulse_mask;
    
    //frame sync helper
    logic vsync_prev;

    //gameplay masks
    logic [19:0] bullet_active_mask;
    logic [9:0] zombie_active_mask;        //active zombie bitmask
    logic [19:0] total_bullet_destroy_mask; //bullets destroyed by zombie hits
    logic [2:0] zombie_hp_array [10];

    logic [1:0] p1_weapon_status; 
    logic [1:0] p2_weapon_status; 
    assign reset_ah = reset_rtl_0;
    logic [10:0] weapon_drop_x [4];
    logic [10:0] weapon_drop_y [4];
    logic [1:0]  weapon_drop_type [4];
    logic [3:0]  weapon_drop_active;
    logic [3:0]  hexA_in [4];
    logic [3:0]  hexB_in [4];

    assign hexA_in[0] = keycode0_gpio[31:28];
    assign hexA_in[1] = keycode0_gpio[27:24];
    assign hexA_in[2] = keycode0_gpio[23:20];
    assign hexA_in[3] = keycode0_gpio[19:16];
    assign hexB_in[0] = keycode0_gpio[15:12];
    assign hexB_in[1] = keycode0_gpio[11:8];
    assign hexB_in[2] = keycode0_gpio[7:4];
    assign hexB_in[3] = keycode0_gpio[3:0];

    //keycode hex drivers
    hex_driver HexA (
        .clk(Clk),
        .reset(reset_ah),
        .in(hexA_in),
        .hex_seg(hex_segA),
        .hex_grid(hex_gridA)
    );
    
    //second hex display uses the lower keycode nibbles
    hex_driver HexB (
        .clk(Clk),
        .reset(reset_ah),
        .in(hexB_in),
        .hex_seg(hex_segB),
        .hex_grid(hex_gridB)
    );
    
    mb_block mb_block_i (
        .clk_100MHz(Clk),
        .gpio_usb_int_tri_i(gpio_usb_int_tri_i),
        .gpio_usb_keycode_0_tri_o(keycode0_gpio),
        .gpio_usb_keycode_1_tri_o(keycode1_gpio),
        .gpio_usb_rst_tri_o(gpio_usb_rst_tri_o),
        .reset_rtl_0(~reset_ah), 
        .uart_rtl_0_rxd(uart_rtl_0_rxd),
        .uart_rtl_0_txd(uart_rtl_0_txd),
        .usb_spi_miso(usb_spi_miso),
        .usb_spi_mosi(usb_spi_mosi),
        .usb_spi_sclk(usb_spi_sclk),
        .usb_spi_ss(usb_spi_ss)
    );
        
    //clock wizard configured with a 1x and 5x clock for hdmi
    clk_wiz_0 clk_wiz (
        .clk_out1(clk_25MHz),
        .clk_out2(clk_125MHz),
        .reset(reset_ah),
        .locked(locked),
        .clk_in1(Clk)
    );
    
    //vga sync signal generator
    vga_controller vga (
        .pixel_clk(clk_25MHz),
        .reset(reset_ah),
        .hs(hsync),
        .vs(vsync),
        .active_nblank(vde),
        .drawX(drawX),
        .drawY(drawY)
    );    

    //real Digital vga to hdmi converter
    hdmi_tx_0 vga_to_hdmi (
        .pix_clk(clk_25MHz),
        .pix_clkx5(clk_125MHz),
        .pix_clk_locked(locked),
        .rst(reset_ah),
        .red(red),
        .green(green),
        .blue(blue),
        .hsync(hsync),
        .vsync(vsync),
        .vde(vde),
        .aux0_din(4'b0),
        .aux1_din(4'b0),
        .aux2_din(4'b0),
        .ade(1'b0),
        .TMDS_CLK_P(hdmi_tmds_clk_p),          
        .TMDS_CLK_N(hdmi_tmds_clk_n),          
        .TMDS_DATA_P(hdmi_tmds_data_p),         
        .TMDS_DATA_N(hdmi_tmds_data_n)          
    );

    //kill counter and death edge detector
    always_ff @(posedge clk_25MHz) begin
        if (reset_ah) begin
            kill_count <= 8'd0;
            zombie_alive_prev <= 10'b0;
            death_pulse_mask <= 10'b0;
            vsync_prev <= 1'b0;
        end else begin
            vsync_prev <= vsync;
            if (vsync_prev == 1'b1 && vsync == 1'b0) begin
                zombie_alive_prev <= zombie_active_mask; 
                death_pulse_mask <= zombie_alive_prev & (~zombie_active_mask);
                
                if ((|(zombie_alive_prev & (~zombie_active_mask))) && kill_count < 8'd100) begin
                    kill_count <= kill_count + 1'b1;
                end
            end
        end
    end


    //color mapper instance
    color_mapper color_instance(
        .clk(clk_25MHz),
        .DrawX(drawX),
        .DrawY(drawY),
        .camera_x(camera_x),     
        .camera_y(camera_y),     

        //player positions
        .p1_x(p1_x), .p1_y(p1_y),
        .p2_x(p2_x), .p2_y(p2_y),

        //player directions
        .p1_dir(p1_dir),   
        .p2_dir(p2_dir),   

        .zombie_x(zombie_x_array),
        .zombie_y(zombie_y_array),
        .zombie_active(zombie_active_mask),
        .zombie_hp(zombie_hp_array),
        
        .bullet_x(bullet_x_array),
        .bullet_y(bullet_y_array),
        .bullet_active(bullet_active_mask),
        
        .pickup_x(pickup_x_array),
        .pickup_y(pickup_y_array),
        .pickup_active(pickup_active_mask),
        .weapon_drop_x(weapon_drop_x),
        .weapon_drop_y(weapon_drop_y),
        .weapon_drop_type(weapon_drop_type),
        .weapon_drop_active(weapon_drop_active),
        //ui state
        .kill_count(kill_count),
        .p1_hp(p1_hp),
        .p2_hp(p2_hp),
        
        .Red(red), .Green(green), .Blue(blue)
    );

    //player controller instance
    player_controller player_ctrl_inst (
        .Clk(clk_25MHz),           
        .Reset(reset_ah),
        .vsync_in(vsync),          
        .keycode(keycode0_gpio[31:0]), 
        
        //damage inputs from zombie collisions
        .p1_damage_flag(total_p1_damage_flag), 
        .p2_damage_flag(total_p2_damage_flag),

        .p1_heal_pulse(p1_heal_pulse),
        .p2_heal_pulse(p2_heal_pulse),
        .weapon_drop_x(weapon_drop_x),
        .weapon_drop_y(weapon_drop_y),
        .weapon_drop_type(weapon_drop_type),
        .weapon_drop_active(weapon_drop_active),
        //player hp outputs
        .p1_hp(p1_hp),
        .p2_hp(p2_hp),

        //player positions
        .p1_x(p1_x), .p1_y(p1_y),
        .p2_x(p2_x), .p2_y(p2_y),

        .camera_x(camera_x),
        .camera_y(camera_y),

        //player directions
        .p1_dir(p1_dir), 
        .p2_dir(p2_dir),

        .player_hit_pulse(player_hit_pulse),
        .p1_weapon(p1_weapon_status),
        .p2_weapon(p2_weapon_status)
    );

    //zombie manager and chase AI
    zombie_manager z_mgr_inst (
        .Clk(clk_25MHz),           
        .Reset(reset_ah),
        .vsync_in(vsync),
        
        //player state used for zombie targeting
        .p1_x(p1_x), .p1_y(p1_y), .p1_hp(p1_hp),
        .p2_x(p2_x), .p2_y(p2_y), .p2_hp(p2_hp),
        
        .bullet_x(bullet_x_array),
        .bullet_y(bullet_y_array),
        .bullet_active(bullet_active_mask),
        
        .zombie_x(zombie_x_array),
        .zombie_y(zombie_y_array),
        .zombie_is_alive(zombie_active_mask),
        .zombie_hp(zombie_hp_array),
        
        .total_bullet_destroy_mask(total_bullet_destroy_mask), 
        
        //aggregated player damage flags
        .total_p1_damage_flag(total_p1_damage_flag),
        .total_p2_damage_flag(total_p2_damage_flag)    
    );

    //bullet controller instance
    bullet_controller bullet_ctrl_inst (
        .Clk(clk_25MHz),           
        .Reset(reset_ah),
        .vsync_in(vsync),          
        .keycode(keycode0_gpio[31:0]), 
        
        .p1_weapon(p1_weapon_status),
        .p2_weapon(p2_weapon_status),
        //player 1 firing inputs
        .p1_x(p1_x),
        .p1_y(p1_y),
        .p1_dir(p1_dir),

        //player 2 firing inputs
        .p2_x(p2_x),
        .p2_y(p2_y),
        .p2_dir(p2_dir),

        .p1_hp(p1_hp),
        .p2_hp(p2_hp),
        
        .bullet_destroy_mask(total_bullet_destroy_mask), 
        
        .bullet_x(bullet_x_array),
        .bullet_y(bullet_y_array),
        .bullet_active(bullet_active_mask),

        .shoot_pulse(shoot_pulse)
    );
    
    //pickup manager instance
    pickup_manager item_mgr_inst (
        .Clk(clk_25MHz),           
        .Reset(reset_ah),
        .vsync_in(vsync),
        
        .zombie_x(zombie_x_array),
        .zombie_y(zombie_y_array),
        .zombie_is_alive(zombie_active_mask),
        
        .p1_x(p1_x),
        .p1_y(p1_y),
        .p2_x(p2_x),
        .p2_y(p2_y),
        .p1_hp(p1_hp),
        .p2_hp(p2_hp),
        
        .pickup_x(pickup_x_array),
        .pickup_y(pickup_y_array),
        .pickup_active(pickup_active_mask),
        .p1_heal_pulse(p1_heal_pulse),
        .p2_heal_pulse(p2_heal_pulse)
    );

    logic audio_out;
    logic shoot_pulse;
    logic player_hit_pulse;
    logic zombie_hit_pulse;

    assign zombie_hit_pulse = |total_bullet_destroy_mask;


    audio_controller audio_ctrl (
        .clk(Clk),
        .reset(reset_ah),

        .shoot_pulse(shoot_pulse),
        .hit_pulse(player_hit_pulse),
        .ugh_pulse(zombie_hit_pulse),

        .audio_out(audio_out)
    );

    assign SPKL = audio_out;
    assign SPKR = audio_out;




endmodule
