module audio_controller (
    input  logic        clk,
    input  logic        reset,

    //trigger signals
    input  logic        shoot_pulse,
    input  logic        hit_pulse,
    input  logic        ugh_pulse,

    //final audio output
    output logic        audio_out
);

    //state machine
    typedef enum logic [1:0] {
        IDLE,
        PLAY_SHOOT,
        PLAY_HIT,
        PLAY_UGH
    } state_t;

    state_t state, next_state;

    //address counter
    logic [15:0] addr;

    //sample (8-bit for PWM)
    logic [7:0] sample;
    logic [15:0] shoot_data;
    logic [15:0] hit_data;
    logic [15:0] ugh_data;
    logic [15:0] shoot_addr;
    logic [15:0] hit_addr;
    logic [15:0] ugh_addr;

    localparam int SAMPLE_DIV = 4535;   //100 mhz / 4535 ~= 22.05 khz
    localparam logic [15:0] SOUND_LEN = 16'd6000; //~= 0.27 s at 22.05 khz

    logic [12:0] sample_divider;
    logic        sample_tick;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            sample_divider <= 13'd0;
            sample_tick <= 1'b0;
        end else if (sample_divider == SAMPLE_DIV - 1) begin
            sample_divider <= 13'd0;
            sample_tick <= 1'b1;
        end else begin
            sample_divider <= sample_divider + 1'b1;
            sample_tick <= 1'b0;
        end
    end

    //pwm counter
    logic [7:0] pwm_counter;

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            pwm_counter <= 8'd0;
        else
            pwm_counter <= pwm_counter + 1'b1;
    end

    assign audio_out = (pwm_counter < sample);

    //state transition
    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (hit_pulse)
                    next_state = PLAY_HIT;
                else if (ugh_pulse)
                    next_state = PLAY_UGH;
                else if (shoot_pulse)
                    next_state = PLAY_SHOOT;
            end

            default: begin
                //return to IDLE when the current sound ends
                if (addr >= SOUND_LEN - 1'b1)
                    next_state = IDLE;
            end
        endcase
    end

    //state update
    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end

    //address logic
    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            addr <= 0;
        else begin
            if (state == IDLE)
                addr <= 0;
            else if (sample_tick && addr < SOUND_LEN - 1'b1)
                addr <= addr + 1;
        end
    end

    //rom select
    always_comb begin
        shoot_addr = addr;
        hit_addr   = addr;
        ugh_addr   = addr;

        case (state)
            PLAY_SHOOT: sample = shoot_data[15:8];
            PLAY_HIT:   sample = hit_data[15:8];
            PLAY_UGH:   sample = ugh_data[15:8];
            default:    sample = 8'd0;
        endcase
    end


    Shoot_rom shoot_rom (
        .clka(clk),
        .ena(1'b1),
        .addra(shoot_addr),
        .douta(shoot_data)
    );

    Hit_rom hit_rom (
        .clka(clk),
        .ena(1'b1),
        .addra(hit_addr),
        .douta(hit_data)
    );

    Ugh_rom ugh_rom (
        .clka(clk),
        .ena(1'b1),
        .addra(ugh_addr),
        .douta(ugh_data)
    );


endmodule
