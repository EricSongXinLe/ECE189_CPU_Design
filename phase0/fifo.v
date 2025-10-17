//synchronous fifo
module fifo #( 
    parameter type T = logic [31:0], 
    parameter DEPTH = 8 
) ( input logic clk, 
    input logic reset, 
    input logic write_en, 
    input T write_data,
    input logic read_en, 
    output T read_data, 
    output logic full, 
    output logic empty);

T Arr[DEPTH-1:0];
logic [2:0] w_ptr, r_ptr;
integer i;

assign empty = (w_ptr == r_ptr);
assign full = ((w_ptr + 3'd1) == r_ptr);

always_ff @ (posedge clk) begin
    if (reset) begin
        for (i = 0; i<DEPTH; i=i+1) begin
            Arr[i] <= '0;
    end
    w_ptr <= '0;
    r_ptr <= '0;
    read_data <= '0;
    end

    if (read_en && (!empty)) begin
        read_data <= Arr[r_ptr];
        r_ptr <= r_ptr + 1;
    end
    if (write_en && (!full || read_en)) begin
        Arr[w_ptr] <= write_data;
        w_ptr <= w_ptr + 1;

    end
end
endmodule


//circular buffer
module c_buffer #( 
    parameter type T = logic [31:0], 
    parameter DEPTH = 8 
) ( input logic clk, 
    input logic reset, 
    input logic write_en, 
    input T write_data,
    input logic read_en, 
    output T read_data, 
    output logic full, 
    output logic empty);

T Arr[DEPTH-1:0];
logic [2:0] w_ptr, r_ptr;
integer i;

assign empty = (w_ptr == r_ptr);
assign full = ((w_ptr + 3'd1) == r_ptr);

always_ff @ (posedge clk) begin
    if (reset) begin
        for (i = 0; i<DEPTH; i=i+1) begin
            Arr[i] <= '0;
    end
    w_ptr <= '0;
    r_ptr <= '0;
    read_data <= '0;
    end

    else begin
        if (read_en && (!empty)) begin
            read_data <= Arr[r_ptr];
            r_ptr <= r_ptr + 1;
        end
        if (write_en && (!full || read_en)) begin
            Arr[w_ptr] <= write_data;
            w_ptr <= w_ptr + 1;
        end
        if (write_en && full && !read_en) begin
            $display ("detect overflow; oldest data discarded");
            Arr[w_ptr] <= write_data;
            w_ptr <= w_ptr + 1;
            r_ptr <= r_ptr + 1;
        end
    end
end
endmodule
