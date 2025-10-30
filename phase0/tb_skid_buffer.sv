`timescale 1ns/1ps

module tb_skid_buffer;

  // ------------------------------------------------------------
  // Parameters / Types
  // ------------------------------------------------------------
  typedef logic [7:0] T;   // simple byte-wide payload

  // ------------------------------------------------------------
  // DUT I/O
  // ------------------------------------------------------------
  logic clk, reset;

  logic valid_in;
  logic ready_in;
  T     data_in;

  logic valid_out;
  logic ready_out;
  T     data_out;

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------
  skid_buffer_struct #(.T(T)) dut (
    .clk,
    .reset,
    .valid_in,
    .ready_in,
    .data_in,
    .valid_out,
    .ready_out,
    .data_out
  );

  // ------------------------------------------------------------
  // Clock
  // ------------------------------------------------------------
  always #5 clk = ~clk;

  // ------------------------------------------------------------
  // Drive tasks
  // ------------------------------------------------------------
  task send(input T d);
    begin
      valid_in <= 1;
      data_in  <= d;
      @(posedge clk);
      // upstream may need to wait if ready_in=0
      while (!ready_in) @(posedge clk);
    end
  endtask

  task stop_send();
    begin
      valid_in <= 0;
      data_in  <= 'x;
    end
  endtask

  // ------------------------------------------------------------
  // Monitor
  // ------------------------------------------------------------
  initial begin
    $display(" time | vin rin din | vout rout dout");
    $monitor("%4t |  %0b   %0b   %0d  |   %0b    %0b    %0d",
             $time, valid_in, ready_in, data_in,
                    valid_out, ready_out, data_out);
  end

  // ------------------------------------------------------------
  // Stimulus
  // ------------------------------------------------------------
  initial begin
    clk = 0;
    reset = 1;
    valid_in = 0;
    ready_out = 1;
    data_in = '0;

    repeat (2) @(posedge clk);
    reset <= 0;

    $display("\n=== Pass-through test ===");
    send(8'h11);
    @(posedge clk);
    stop_send();
    @(posedge clk);

    $display("\n=== Downstream stall (skid) ===");
    ready_out <= 1;
    send(8'h22);
    @(posedge clk);

    // Stall downstream → should capture
    ready_out <= 0;
    send(8'h33);   // this one should SKID
    @(posedge clk);
    stop_send();
    @(posedge clk);

    // Still stalled → should HOLD
    @(posedge clk);

    $display("\n=== Release stall (drain skid) ===");
    ready_out <= 1;   // now downstream takes skid data
    @(posedge clk);

    // one more cycle
    @(posedge clk);

    $display("\n=== Swap test (consume + refill same cycle) ===");
    // Hold another value, downstream ready
    ready_out <= 1;
    send(8'h44);   // pass
    send(8'h55);   // swap
    @(posedge clk);
    stop_send();

    repeat (5) @(posedge clk);
    $finish;
  end

endmodule
//Citation: ChatGPT generated testbench