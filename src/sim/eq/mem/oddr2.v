// ODDR2 of Spartan-6 for the simulation (DDR_ALIGNMENT "NONE": D0 taken at the rise of C0, D1 at the rise of C1).
`timescale 1ns/1ps
module ODDR2 #(parameter DDR_ALIGNMENT = "NONE", parameter INIT = 1'b0, parameter SRTYPE = "SYNC")
	(output reg Q = INIT, input C0, input C1, input CE, input D0, input D1, input R, input S);
	always @(posedge C0) if (R) Q <= 1'b0; else if (S) Q <= 1'b1; else if (CE) Q <= D0;
	always @(posedge C1) if (R) Q <= 1'b0; else if (S) Q <= 1'b1; else if (CE) Q <= D1;
endmodule
// IDDR2 of Spartan-6 for the simulation (DDR_ALIGNMENT "NONE": Q0 = D at the rise of C0, Q1 = D at the rise of C1).
module IDDR2 #(parameter DDR_ALIGNMENT = "NONE", parameter INIT_Q0 = 1'b0, parameter INIT_Q1 = 1'b0,
	parameter SRTYPE = "SYNC")
	(output reg Q0 = INIT_Q0, output reg Q1 = INIT_Q1, input C0, input C1, input CE, input D, input R, input S);
	always @(posedge C0) if (R) Q0 <= 1'b0; else if (S) Q0 <= 1'b1; else if (CE) Q0 <= D;
	always @(posedge C1) if (R) Q1 <= 1'b0; else if (S) Q1 <= 1'b1; else if (CE) Q1 <= D;
endmodule
