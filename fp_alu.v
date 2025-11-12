// ============================================================================
// IEEE 754-2008 Single Precision Floating Point Arithmetic Unit
// 32-bit FP: Sign(1) | Exponent(8) | Mantissa(23)
// Operations: ADD, SUB, MUL, DIV
// ============================================================================

module fp_alu (
    input wire clk,
    input wire rst_n,
    input wire [31:0] operand_a,
    input wire [31:0] operand_b,
    input wire [1:0] operation,  // 00=ADD, 01=SUB, 10=MUL, 11=DIV
    input wire start,
    output reg [31:0] result,
    output reg done,
    output reg overflow,
    output reg underflow,
    output reg invalid
);

    // Operation codes
    localparam OP_ADD = 2'b00;
    localparam OP_SUB = 2'b01;
    localparam OP_MUL = 2'b10;
    localparam OP_DIV = 2'b11;
    
    // Special values
    localparam [7:0] EXP_INF = 8'hFF;
    localparam [7:0] EXP_ZERO = 8'h00;
    localparam [7:0] BIAS = 8'd127;
    
    // Extract fields from operands
    wire sign_a, sign_b;
    wire [7:0] exp_a, exp_b;
    wire [22:0] frac_a, frac_b;
    
    assign sign_a = operand_a[31];
    assign exp_a = operand_a[30:23];
    assign frac_a = operand_a[22:0];
    
    assign sign_b = operand_b[31];
    assign exp_b = operand_b[30:23];
    assign frac_b = operand_b[22:0];
    
    // Check for special cases
    wire zero_a = (exp_a == 0) && (frac_a == 0);
    wire zero_b = (exp_b == 0) && (frac_b == 0);
    wire inf_a = (exp_a == EXP_INF) && (frac_a == 0);
    wire inf_b = (exp_b == EXP_INF) && (frac_b == 0);
    wire nan_a = (exp_a == EXP_INF) && (frac_a != 0);
    wire nan_b = (exp_b == EXP_INF) && (frac_b != 0);
    wire denorm_a = (exp_a == 0) && (frac_a != 0);
    wire denorm_b = (exp_b == 0) && (frac_b != 0);
    
    // State machine for multi-cycle operations
    reg [2:0] state;
    reg [1:0] op_reg;
    
    localparam IDLE = 3'd0;
    localparam CALC = 3'd1;
    localparam NORM = 3'd2;
    localparam ROUND = 3'd3;
    localparam DONE = 3'd4;
    
    // Internal registers for computation
    reg sign_res;
    reg [9:0] exp_res;  // Extended for overflow/underflow detection
    reg [47:0] frac_res; // Extended for precision
    
    // Division specific registers
    reg [5:0] div_count;
    reg [47:0] dividend;
    reg [23:0] divisor;
    
    // ========================================================================
    // Main FSM
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;
            result <= 32'h0;
            overflow <= 0;
            underflow <= 0;
            invalid <= 0;
            op_reg <= 2'b00;
            div_count <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    overflow <= 0;
                    underflow <= 0;
                    invalid <= 0;
                    
                    if (start) begin
                        op_reg <= operation;
                        
                        // Handle special cases immediately
                        if (nan_a || nan_b) begin
                            result <= 32'h7FC00000; // QNaN
                            invalid <= 1;
                            state <= DONE;
                        end else begin
                            case (operation)
                                OP_ADD, OP_SUB: begin
                                    fp_add_sub();
                                    state <= NORM;
                                end
                                OP_MUL: begin
                                    fp_multiply();
                                    state <= NORM;
                                end
                                OP_DIV: begin
                                    if (zero_b) begin
                                        if (zero_a) begin
                                            result <= 32'h7FC00000; // NaN
                                            invalid <= 1;
                                        end else begin
                                            result <= {sign_a ^ sign_b, 8'hFF, 23'h0}; // Inf
                                            invalid <= 1;
                                        end
                                        state <= DONE;
                                    end else begin
                                        fp_divide_init();
                                        state <= CALC;
                                        div_count <= 0;
                                    end
                                end
                            endcase
                        end
                    end
                end
                
                CALC: begin
                    // Division iteration
                    if (div_count < 24) begin
                        fp_divide_iter();
                        div_count <= div_count + 1;
                    end else begin
                        state <= NORM;
                    end
                end
                
                NORM: begin
                    normalize();
                    state <= ROUND;
                end
                
                ROUND: begin
                    round_result();
                    state <= DONE;
                end
                
                DONE: begin
                    done <= 1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    // ========================================================================
    // Addition/Subtraction
    // ========================================================================
    task fp_add_sub;
        reg [23:0] mant_a, mant_b;
        reg [7:0] exp_diff;
        reg [24:0] aligned_a, aligned_b;
        reg [24:0] sum;
        reg effective_sub;
        
        begin
            // Handle zero operands
            if (zero_a && zero_b) begin
                sign_res = (operation == OP_SUB) ? sign_a & ~sign_b : sign_a & sign_b;
                exp_res = 0;
                frac_res = 0;
            end else if (zero_a) begin
                sign_res = (operation == OP_SUB) ? ~sign_b : sign_b;
                exp_res = exp_b;
                frac_res = {frac_b, 24'h0};
            end else if (zero_b) begin
                sign_res = sign_a;
                exp_res = exp_a;
                frac_res = {frac_a, 24'h0};
            end else if (inf_a || inf_b) begin
                // Handle infinities
                if (inf_a && inf_b) begin
                    effective_sub = (operation == OP_SUB) ? (sign_a != sign_b) : (sign_a == sign_b);
                    if (!effective_sub) begin
                        invalid = 1;
                        result = 32'h7FC00000; // NaN
                    end else begin
                        sign_res = sign_a;
                        exp_res = 8'hFF;
                        frac_res = 0;
                    end
                end else if (inf_a) begin
                    sign_res = sign_a;
                    exp_res = 8'hFF;
                    frac_res = 0;
                end else begin
                    sign_res = (operation == OP_SUB) ? ~sign_b : sign_b;
                    exp_res = 8'hFF;
                    frac_res = 0;
                end
            end else begin
                // Normal computation
                // Add implicit leading 1
                mant_a = {1'b1, frac_a};
                mant_b = {1'b1, frac_b};
                
                // Align exponents
                if (exp_a > exp_b) begin
                    exp_diff = exp_a - exp_b;
                    exp_res = exp_a;
                    aligned_a = {mant_a, 1'b0};
                    aligned_b = (exp_diff > 24) ? 25'h0 : ({mant_b, 1'b0} >> exp_diff);
                end else begin
                    exp_diff = exp_b - exp_a;
                    exp_res = exp_b;
                    aligned_a = (exp_diff > 24) ? 25'h0 : ({mant_a, 1'b0} >> exp_diff);
                    aligned_b = {mant_b, 1'b0};
                end
                
                // Determine effective operation
                effective_sub = (operation == OP_SUB) ? (sign_a != sign_b) : (sign_a == sign_b);
                
                if (!effective_sub) begin
                    // Effective subtraction
                    if (aligned_a >= aligned_b) begin
                        sum = aligned_a - aligned_b;
                        sign_res = sign_a;
                    end else begin
                        sum = aligned_b - aligned_a;
                        sign_res = (operation == OP_SUB) ? ~sign_b : sign_b;
                    end
                end else begin
                    // Addition
                    sum = aligned_a + aligned_b;
                    sign_res = sign_a;
                end
                
                frac_res = {sum, 23'h0};
            end
        end
    endtask
    
    // ========================================================================
    // Multiplication
    // ========================================================================
    task fp_multiply;
        reg [47:0] product;
        reg [9:0] exp_sum;
        
        begin
            if (zero_a || zero_b) begin
                sign_res = sign_a ^ sign_b;
                exp_res = 0;
                frac_res = 0;
            end else if (inf_a || inf_b) begin
                sign_res = sign_a ^ sign_b;
                exp_res = 8'hFF;
                frac_res = 0;
            end else begin
                // Normal multiplication
                sign_res = sign_a ^ sign_b;
                
                // Multiply mantissas (with implicit 1)
                product = {1'b1, frac_a} * {1'b1, frac_b};
                frac_res = product;
                
                // Add exponents and subtract bias
                exp_sum = exp_a + exp_b - BIAS;
                exp_res = exp_sum;
            end
        end
    endtask
    
    // ========================================================================
    // Division Initialization
    // ========================================================================
    task fp_divide_init;
        begin
            sign_res = sign_a ^ sign_b;
            
            if (zero_a) begin
                exp_res = 0;
                frac_res = 0;
            end else if (inf_a) begin
                exp_res = 8'hFF;
                frac_res = 0;
            end else begin
                // Initialize division
                dividend = {1'b1, frac_a, 24'h0};
                divisor = {1'b1, frac_b};
                exp_res = exp_a - exp_b + BIAS;
                frac_res = 0;
            end
        end
    endtask
    
    // ========================================================================
    // Division Iteration (Non-restoring)
    // ========================================================================
    task fp_divide_iter;
        reg [47:0] temp;
        begin
            temp = dividend - {divisor, 24'h0};
            if (temp[47] == 0) begin
                // Subtraction successful
                frac_res = {frac_res[46:0], 1'b1};
                dividend = {temp[46:0], 1'b0};
            end else begin
                // Subtraction failed
                frac_res = {frac_res[46:0], 1'b0};
                dividend = {dividend[46:0], 1'b0};
            end
        end
    endtask
    
    // ========================================================================
    // Normalization
    // ========================================================================
    task normalize;
        integer i;
        begin
            // Find leading 1
            if (frac_res == 0) begin
                exp_res = 0;
            end else if (frac_res[47]) begin
                // Overflow in MSB, shift right
                frac_res = frac_res >> 1;
                exp_res = exp_res + 1;
            end else begin
                // Normalize by shifting left
                for (i = 46; i >= 0; i = i - 1) begin
                    if (frac_res[i]) begin
                        frac_res = frac_res << (46 - i);
                        exp_res = exp_res - (46 - i);
                        i = -1; // Break loop
                    end
                end
            end
            
            // Check for overflow/underflow
            if (exp_res >= 10'h0FF) begin
                overflow = 1;
                exp_res = 8'hFF;
                frac_res = 0;
            end else if (exp_res <= 0) begin
                underflow = 1;
                exp_res = 0;
                frac_res = 0;
            end
        end
    endtask
    
    // ========================================================================
    // Rounding (Round to nearest, ties to even)
    // ========================================================================
    task round_result;
        reg [22:0] rounded_frac;
        reg guard, round_bit, sticky;
        
        begin
            // Extract rounding bits
            guard = frac_res[23];
            round_bit = frac_res[22];
            sticky = |frac_res[21:0];
            
            rounded_frac = frac_res[46:24];
            
            // Round to nearest, ties to even
            if (guard && (round_bit || sticky || rounded_frac[0])) begin
                rounded_frac = rounded_frac + 1;
                if (rounded_frac == 0) begin
                    // Mantissa overflow
                    exp_res = exp_res + 1;
                end
            end
            
            // Assemble final result
            result = {sign_res, exp_res[7:0], rounded_frac};
        end
    endtask

endmodule
