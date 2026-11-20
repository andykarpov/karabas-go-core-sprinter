// ODDR2 of Spartan-6 for the simulation (DDR_ALIGNMENT "NONE": D0 taken at the rise of C0, D1 at the rise of C1).
`timescale 1ns/1ps
module ODDR2 #(parameter DDR_ALIGNMENT = "NONE", parameter INIT = 1'b0, parameter SRTYPE = "SYNC")
	(output reg Q = INIT, input C0, input C1, input CE, input D0, input D1, input R, input S);
	always @(posedge C0) if (R) Q <= 1'b0; else if (S) Q <= 1'b1; else if (CE) Q <= D0;
	always @(posedge C1) if (R) Q <= 1'b0; else if (S) Q <= 1'b1; else if (CE) Q <= D1;
endmodule
