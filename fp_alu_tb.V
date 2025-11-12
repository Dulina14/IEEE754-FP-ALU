
// ============================================================================
// Testbench
// ============================================================================
module fp_alu_tb;
    reg clk;
    reg rst_n;
    reg [31:0] operand_a;
    reg [31:0] operand_b;
    reg [1:0] operation;
    reg start;
    wire [31:0] result;
    wire done;
    wire overflow;
    wire underflow;
    wire invalid;
    
    fp_alu uut (
        .clk(clk),
        .rst_n(rst_n),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .operation(operation),
        .start(start),
        .result(result),
        .done(done),
        .overflow(overflow),
        .underflow(underflow),
        .invalid(invalid)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test cases
    initial begin
        $dumpfile("fp_alu.vcd");
        $dumpvars(0, fp_alu_tb);
        
        // Initialize
        rst_n = 0;
        start = 0;
        #20 rst_n = 1;
        
        // Test 1: Addition - 3.5 + 2.25 = 5.75
        #10;
        operand_a = 32'h40600000; // 3.5
        operand_b = 32'h40100000; // 2.25
        operation = 2'b00;
        start = 1;
        #10 start = 0;
        wait(done);
        $display("Test 1 - ADD: 3.5 + 2.25 = %h (Expected: 40B80000)", result);
        
        // Test 2: Subtraction - 10.0 - 3.0 = 7.0
        #20;
        operand_a = 32'h41200000; // 10.0
        operand_b = 32'h40400000; // 3.0
        operation = 2'b01;
        start = 1;
        #10 start = 0;
        wait(done);
        $display("Test 2 - SUB: 10.0 - 3.0 = %h (Expected: 40E00000)", result);
        
        // Test 3: Multiplication - 2.5 * 4.0 = 10.0
        #20;
        operand_a = 32'h40200000; // 2.5
        operand_b = 32'h40800000; // 4.0
        operation = 2'b10;
        start = 1;
        #10 start = 0;
        wait(done);
        $display("Test 3 - MUL: 2.5 * 4.0 = %h (Expected: 41200000)", result);
        
        // Test 4: Division - 10.0 / 2.0 = 5.0
        #20;
        operand_a = 32'h41200000; // 10.0
        operand_b = 32'h40000000; // 2.0
        operation = 2'b11;
        start = 1;
        #10 start = 0;
        wait(done);
        $display("Test 4 - DIV: 10.0 / 2.0 = %h (Expected: 40A00000)", result);
        
        // Test 5: Division by zero
        #20;
        operand_a = 32'h40200000; // 2.5
        operand_b = 32'h00000000; // 0.0
        operation = 2'b11;
        start = 1;
        #10 start = 0;
        wait(done);
        $display("Test 5 - DIV by zero: Invalid=%b", invalid);
        
        #100;
        $finish;
    end
endmodule
