
`timescale 1ns / 1ps

module fp_alu(
    input clk,
    input reset,
    input start,
    input [31:0] operand_a,
    input [31:0] operand_b,
    input [2:0] opcode,
    output reg [31:0] result,
    output reg invalid,
    output reg ready
);

    // Opcodes
    localparam OP_ADD = 3'b000;
    localparam OP_SUB = 3'b001;
    localparam OP_MUL = 3'b010;
    localparam OP_DIV = 3'b011;

    // FSM states
    localparam IDLE = 3'd0;
    localparam UNPACK = 3'd1;
    localparam CALCULATE = 3'd2;
    localparam NORMALIZE = 3'd3;
    localparam ROUND = 3'd4;
    localparam PACK = 3'd5;
    localparam DONE = 3'd6;

    reg [2:0] state = IDLE;

    // Operands unpacked
    reg sign_a, sign_b;
    reg [7:0] exp_a, exp_b;
    reg [23:0] man_a, man_b;

    // Intermediate result
    reg sign_res;
    reg [8:0] exp_res;
    reg [47:0] man_res;
    
    // For division
    reg [47:0] quotient;
    reg [48:0] remainder;


    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            ready <= 1;
            invalid <= 0;
            result <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start && ready) begin
                        ready <= 0;
                        state <= UNPACK;
                    end
                end
                
                UNPACK: begin
                    sign_a <= operand_a[31];
                    exp_a  <= operand_a[30:23];
                    man_a  <= (operand_a[30:0] == 0) ? 24'd0 : {1'b1, operand_a[22:0]};

                    sign_b <= operand_b[31];
                    exp_b  <= operand_b[30:23];
                    man_b  <= (operand_b[30:0] == 0) ? 24'd0 : {1'b1, operand_b[22:0]};
                    state <= CALCULATE;
                end
                
                CALCULATE: begin
                    invalid <= 0;
                    case (opcode)
                        OP_ADD, OP_SUB: fp_add_sub();
                        OP_MUL: fp_multiply();
                        OP_DIV: fp_divide();
                    endcase
                    state <= NORMALIZE;
                end

                NORMALIZE: begin
                    normalize();
                    state <= ROUND;
                end

                ROUND: begin
                    round_result();
                    state <= PACK;
                end
                
                PACK: begin
                    result <= {sign_res, exp_res[7:0], man_res[22:0]};
                    state <= DONE;
                end

                DONE: begin
                    ready <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

    task fp_add_sub;
        reg [8:0] exp_a_ext, exp_b_ext;
        reg [25:0] man_a_ext, man_b_ext;
        reg [8:0] exp_diff;
        reg sign_b_eff;
        reg [26:0] man_res_addsub;
    begin
        exp_a_ext = {1'b0, exp_a};
        exp_b_ext = {1'b0, exp_b};
        man_a_ext = {man_a, 2'b00};
        man_b_ext = {man_b, 2'b00};

        if (exp_a_ext > exp_b_ext) begin
            exp_diff = exp_a_ext - exp_b_ext;
            man_b_ext = man_b_ext >> exp_diff;
            exp_res = exp_a_ext;
        end else begin
            exp_diff = exp_b_ext - exp_a_ext;
            man_a_ext = man_a_ext >> exp_diff;
            exp_res = exp_b_ext;
        end

        sign_b_eff = sign_b ^ (opcode == OP_SUB);

        if (sign_a == sign_b_eff) begin // Effective addition
            man_res_addsub = {1'b0, man_a_ext} + {1'b0, man_b_ext};
            sign_res = sign_a;
        end else begin // Effective subtraction
            if (man_a_ext >= man_b_ext) begin
                man_res_addsub = man_a_ext - man_b_ext;
                sign_res = sign_a;
            end else begin
                man_res_addsub = man_b_ext - man_a_ext;
                sign_res = sign_b_eff;
            end
        end
        man_res = man_res_addsub << 21;
    end
    endtask
    
    task fp_multiply;
    begin
        sign_res = sign_a ^ sign_b;
        exp_res = exp_a + exp_b - 127;
        man_res = man_a * man_b;
    end
    endtask

    task fp_divide;
    begin
        if (|man_b == 0) begin // Division by zero
            invalid <= 1;
            man_res <= 48'd0;
            exp_res <= 9'd0;
            sign_res <= 1'b0;
        end else begin
            sign_res = sign_a ^ sign_b;
            exp_res = exp_a - exp_b + 127;
            fp_divide_iter({man_a, 25'd0}, man_b);
            man_res = quotient << 21;
        end
    end
    endtask
    
    task fp_divide_iter;
        input [48:0] dividend;
        input [23:0] divisor;
        integer i;
    begin
        remainder = dividend;
        quotient = 0;

        for (i=0; i<25; i=i+1) begin
            remainder = remainder << 1;
            if (remainder[48:24] >= divisor) begin
                remainder[48:24] = remainder[48:24] - divisor;
                quotient[24-i] = 1;
            end
        end
    end
    endtask

    task normalize;
    begin
        if (man_res == 0) begin
            exp_res = 0;
        end else if (man_res >= {2'b10, 46'd0}) begin
            while (man_res >= {2'b10, 46'd0}) begin
                 man_res = man_res >> 1;
                 exp_res = exp_res + 1;
            end
        end else begin
            while (man_res < {2'b01, 46'd0}) begin
                man_res = man_res << 1;
                exp_res = exp_res - 1;
            end
        end
    end
    endtask
    
    task round_result;
        reg round_bit;
    begin
        round_bit = man_res[22];
        man_res = (man_res >> 23) + round_bit;

        if (man_res >= {2'b10, 23'd0}) begin
            man_res = man_res >> 1;
            exp_res = exp_res + 1;
        end
    end
    endtask

endmodule
