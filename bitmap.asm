#	Bitmap Project by Reid Smith
#
#	MIPSelbrot: A MIPS Assembly Language Mandelbrot Set Explorer
#
#	Features:
#	-Visualizes Mandelbrot and Julia Set(s) in MIPS Bitmap
#	-Controllable User Perspective
#
#	Bitmap Settings:
#	-PIXEL_SIDE = Diplay / Unit <= 128 (Basically just have a unit resolution of up to 128x128)
#	-BASE_BITMAP_ADDRESS = Base address = global data, $gp, static data, heap (Doesn't matter, just try another if one doesn't work at first)
#
#	Controls:
#	-Pan View with `w`, `a`, `s`, `d` 
#	-Zoom View ith `+` and `-`
#	-Enter Frame Specifications (x-min, x-max, y-min, y-max) `f`
#	-Toggle between Mandelbrot and Julia Set with `t`
#	-Specify Julia Candidate Value with `c`
#	-Toggle between BW and Color modes with `m`

.eqv PIXEL_SIDE, 128
.eqv BASE_BITMAP_ADDRESS, 0x10040000

.data

addition_res:	.space 8
square_res:	.space 8
magnitude_res:	.space 4
real_min:	.float -2
real_max:	.float 1
complex_min:	.float -1.5
complex_max:	.float 1.5
saved_real_min:	.float -2
saved_real_max:	.float 1
saved_complex_min:	.float -1.5
saved_complex_max:	.float 1.5
noncandidate_value:	.space 8
zoom_multiplier:.float 1.333333
pan_offset:	.float 0.333333
input_msg:	.asciiz "Waiting for input now"
got_input_msg:	.asciiz "Recieved input key "
noncandidate_real_msg:	.asciiz "Please enter the real part of the non-candidate value (or nothing to stay the same)"
noncandidate_complex_msg:	.asciiz "Please enter the complex part of the non-candidate value (or nothing to stay the same)"
real_min_msg:	.asciiz "Please enter the real minimum value of the frame view (or nothing to stay the same)"
real_max_msg:	.asciiz "Please enter the real maximum value of the frame view (or nothing to stay the same)"
complex_min_msg:	.asciiz "Please enter the complex minimum value of the frame view (or nothing to stay the same)"
complex_max_msg:	.asciiz "Please enter the complex maximum value of the frame view (or nothing to stay the same)"
input_error_msg:	.asciiz "Error during user input, no change made to values"
color_list:	.word 0x006e92fa, 0x00788aef, 0x008082e3, 0x00867bd7, 0x008a74cb, 0x008d6dbf, 0x008e66b3, 0x008e5fa8, 0x008d599c, 0x008c5391, 0x00894e86, 0x0086497b, 0x00824471, 0x007d3f67, 0x00783b5e, 0x00723755, 0x006c344c, 0x00663044, 0x005f2d3d, 0x00582a36


.text
main:
	la	$a0, input_msg #Output waiting for input message
	li	$v0, 4
	syscall
	li	$v0, 11
	li	$a0, 10
	syscall
	main_loop:
	lw 	$t4, 0xFFFF0000		#Check if user input
	beq	$zero, $t4, main_loop
	jal	user_modifications
	jal	clear_screen
	jal	draw_set
	la	$a0, input_msg	#Output waiting for input message
	li	$v0, 4
	syscall
	j	main_loop
exit:
	li 	$v0, 10
	syscall
	
#s1 = mandel or julia
#s2 = bounded or banded
#s3 = bw or color
	
# ---- Function Definitions ---- #

#Name: Draw Pixel
#Paramters: $a0 = bounded, $a1 = pixel_x, $a2 = pixel_y, $a3 = num_iterations
#Modifies: t2, (t2), 
#Returns: None
draw_pixel:
    	# t2 = address = MEM + 4*(x + y*width)
    	addi	$sp, $sp, -4
    	sw	$t0, ($sp)
	mul    	$t2, $a2, PIXEL_SIDE   # s1 = y * WIDTH
	add    	$t2, $t2, $a1      # s1 += x
	mul    	$t2, $t2, 4      # s1 *= 4 (for word offset
	add    	$t2, $t2, BASE_BITMAP_ADDRESS      # s1 += base address
	
	bne 	$0, $s2, make_banded	#Break if graph is banded
	beq 	$0, $a0, pixel_not_bounded
	
	bne	$0, $s3, pixel_bounded_color
	li	$t0, 0x00FFFFFF
	j	store_pixel

	pixel_bounded_color:
	li	$t0, 0x00582a36
	j 	store_pixel
	
	pixel_not_bounded:
	bne	$0, $s3, pixel_not_bounded_color
	li 	$t0, 0
	j 	store_pixel
	
	pixel_not_bounded_color:
	li	$t0, 0x006e92fa
	j	store_pixel
	
	make_banded:
	bne	$0, $s3, make_banded_color
	mul	$a3, $a3, 12
	add	$t0, $0, $a3
	sll	$t0, $t0, 8
	add	$t0, $t0, $a3
	sll	$t0, $t0, 8
	add	$t0, $t0, $a3
	j	store_pixel

	make_banded_color:
	sll	$a3, $a3, 2
	la	$t0, color_list
	add	$t0, $t0, $a3
	lw	$t0, ($t0)
	
	store_pixel:
	sw	$t0, 0($t2)      # store pixel color
	
	lw	$t0, ($sp)
	addi	$sp, $sp, 4
	jr     	$ra
    
    
#Name: Is Bounded?
#Parameters: $f6 = Initial Z-Value Real Part, $f7 = Initial Z-Value Complex Part , $f8 = Candiate Value Real Part, $f9 = Candidate Value Complex Part
#Modifies: t3-4, f6/7, f10-12
#Returns: $v0 = 1 if bounded, 0 else, $v1 = # of iterations sucessfully bounded
is_bounded:
	li 	$t3, 0	#t3 = Cycle Index
	li 	$t4, 15	#t4 = Maximum Cycles
	li 	$t5, 4		
	mtc1 	$t5, $f12
	cvt.s.w $f12, $f12	#f12 = 4.0
	
	bound_loop:
	bne 	$t3, $t4, bound_not_max	#If not max cycle, continue loop
	li 	$v0, 1
	move	$v1, $t3
	jr 	$ra
	
	bound_not_max:
	mul.s	$f10, $f6, $f6 
	mul.s	$f11, $f7, $f7
	add.s	$f10, $f10, $f11#f10 = magnitude^2 of z
	c.le.s 	$f10, $f12
	bc1t 	bound_not_diverged	#If not diverged, continue loop
	li 	$v0, 0
	move	$v1, $t3
	jr 	$ra
	
	bound_not_diverged:
	mul.s	$f10, $f6, $f7
	add.s	$f10, $f10, $f10
	mul.s	$f6, $f6, $f6
	mul.s	$f7, $f7, $f7
	sub.s	$f6, $f6, $f7
	mov.s	$f7, $f10	#f6,f7 = (Z-Value)^2
	
	add.s	$f6, $f6, $f8
	add.s	$f7, $f7, $f9	#f6,f7 = Z-Value + Candidate

	addiu 	$t3, $t3, 1 	#Increment Cycle and Restart Loop
	j bound_loop


#Name: Draw (Mandelbrot/Julia) Set
#Parameters: real_min/max, complex_min/max, color?, s1, nontest-value
#Modifies: Bitmap, v0-1, t0-2, f0-12
#Returns: None
draw_set:
	addi 	$sp, $sp, -4 	#Save Return Address and t0-2
	sw 	$ra, ($sp)	
	
	li 	$t0, 0	#t0 = pixel_x
	li	$t1, 0	#t1 = pixel_y	
	
	la	$t2, noncandidate_value
	l.s	$f29, 0($t2)	#f29 = z_real for Mandelbrot / c_real for Julia
	l.s	$f30, 4($t2)	#f30 = z_complex for Mandelbrot / c_complex for Julia
	
	li 	$t2, PIXEL_SIDE
	mtc1	$t2, $f31
	cvt.s.w $f31, $f31	#f31 = float(PIXEL_SIDE)
	
	l.s	$f0, real_min	#f0 = Candidate Real Value
	l.s	$f1, real_max	#f1 = Max Real Value
	sub.s	$f2, $f1, $f0
	div.s	$f2, $f2, $f31	#f2 = Real Value Increment
	
	l.s	$f3, complex_max#f3 = Candidate Complex Value
	l.s	$f4, complex_min#f4 = Min Complex Value
	sub.s	$f5, $f4, $f3
	div.s	$f5, $f5, $f31	#f5 = Complex Value Decrement

	loop_pixel_y:
	beq	$t1, PIXEL_SIDE, after_loop_pixel_y	#Break loop if reached last pixel
	l.s 	$f0, real_min	#Reset Real Value
	li	$t0, 0		#Reset pixel_x
	
	loop_pixel_x:
	beq	$t0, PIXEL_SIDE, after_loop_pixel_x
	
	bne	$0, $s1, julia_values	#Break if drawing Julia Set and not Mandelbrot Set
	mov.s	$f6, $f29	#f6 = Testing Z-Value Real = 0 
	mov.s	$f7, $f30	#f7 = Testing Z-Value Complex = 0
	mov.s	$f8, $f0	#f8 = Testing C-Value Real = r
	mov.s	$f9, $f3	#f9 = Testing C-Value Complex = i
	j 	check_bounds
	
	julia_values:	
	mov.s	$f6, $f0	#f6 = r
	mov.s	$f7, $f3	#f7 = i
	mov.s	$f8, $f29	#f8 = Constant real
	mov.s	$f9, $f30	#f9 = Constant complex

	check_bounds:

	jal is_bounded
	
	move	$a0, $v0
	move	$a1, $t0
	move	$a2, $t1
	move	$a3, $v1
	jal 	draw_pixel
	
	add.s 	$f0, $f0, $f2	#Increment Real Value
	addiu	$t0, $t0, 1	#Increment pixel_x
	j 	loop_pixel_x
	
	after_loop_pixel_x:
	add.s 	$f3, $f3, $f5	#Decrement Complex Value
	addiu	$t1, $t1, 1	#increment pixel_y
	j	loop_pixel_y
	
	after_loop_pixel_y:
	
	lw 	$ra, ($sp) 
	addi 	$sp, $sp, 4
	jr 	$ra

#Name: (Get) User Modifications
#Parameters: 
#Modifies: 
#Returns: 
user_modifications:
	lw	$t4, 0xFFFF0004
	la	$a0, got_input_msg	#Output input message
	li	$v0, 4
	syscall
	move 	$a0, $t4
	li 	$v0, 11
	syscall
	li	$a0, 10
	syscall
	
	zoom_in:
	bne	$t4, 43, zoom_out	# '+' Zoom in graph
	l.s	$f1, zoom_multiplier
	l.s	$f0, real_min
	div.s	$f0, $f0, $f1
	swc1	$f0, real_min
	l.s	$f0, real_max
	div.s	$f0, $f0, $f1
	swc1	$f0, real_max
	l.s	$f0, complex_min
	div.s	$f0, $f0, $f1
	swc1	$f0, complex_min
	l.s	$f0, complex_max
	div.s	$f0, $f0, $f1
	swc1	$f0, complex_max
	mtc1	$zero, $f0
	mtc1	$zero, $f1
	j	end_modifications
	
	zoom_out:
	bne	$t4, 45, pan_left	# '-' Zoom out graph
	l.s	$f1, zoom_multiplier
	l.s	$f0, real_min
	mul.s	$f0, $f0, $f1
	swc1	$f0, real_min
	l.s	$f0, real_max
	mul.s	$f0, $f0, $f1
	swc1	$f0, real_max
	l.s	$f0, complex_min
	mul.s	$f0, $f0, $f1
	swc1	$f0, complex_min
	l.s	$f0, complex_max
	mul.s	$f0, $f0, $f1
	swc1	$f0, complex_max
	mtc1	$zero, $f0
	mtc1	$zero, $f1
	j	end_modifications
	
	pan_left:
	bne	$t4, 97, pan_right	# 'a' Pan graph left
	l.s	$f1, pan_offset
	l.s	$f0, real_min
	l.s	$f2, real_max
	sub.s	$f0, $f2, $f0
	mul.s	$f0, $f0, $f1
	sub.s	$f2, $f2, $f0
	swc1	$f2, real_max
	l.s	$f2, real_min
	sub.s	$f2, $f2, $f0
	swc1	$f2, real_min
	j	end_modifications
	
	pan_right:
	bne	$t4, 100, pan_up	# 'd' Pan graph right
	l.s	$f1, pan_offset
	l.s	$f0, real_min
	l.s	$f2, real_max
	sub.s	$f0, $f2, $f0
	mul.s	$f0, $f0, $f1
	add.s	$f2, $f2, $f0
	swc1	$f2, real_max
	l.s	$f2, real_min
	add.s	$f2, $f2, $f0
	swc1	$f2, real_min
	j	end_modifications
	
	pan_up:
	bne	$t4, 119, pan_down	# 'w' Pan graph up
	l.s	$f1, pan_offset
	l.s	$f0, complex_min
	l.s	$f2, complex_max
	sub.s	$f0, $f2, $f0
	mul.s	$f0, $f0, $f1
	add.s	$f2, $f2, $f0
	swc1	$f2, complex_max
	l.s	$f2, complex_min
	add.s	$f2, $f2, $f0
	swc1	$f2, complex_min
	j	end_modifications
	
	pan_down:
	bne	$t4, 115, color_reg	# 's' Pan graph down
	l.s	$f1, pan_offset
	l.s	$f0, complex_min
	l.s	$f2, complex_max
	sub.s	$f0, $f2, $f0
	mul.s	$f0, $f0, $f1
	sub.s	$f2, $f2, $f0
	swc1	$f2, complex_max
	l.s	$f2, complex_min
	sub.s	$f2, $f2, $f0
	swc1	$f2, complex_min
	j	end_modifications

	color_reg:
	bne	$t4, 114, color_bands	# 'r' Draw set with default settings (Mandelbrot, bw, no bands, default frame, noncandidate = 0)
	li	$s2, 0
	li	$s3, 0
	lw	$t4, saved_real_min
	sw	$t4, real_min
	lw	$t4, saved_real_max
	sw	$t4, real_max
	lw	$t4, saved_complex_min
	sw	$t4, complex_min
	lw	$t4, saved_complex_max
	sw	$t4, complex_max
	la	$t4, noncandidate_value
	sw	$0, 0($t4)
	sw	$0, 4($t4)
	j	end_modifications
	
	color_bands:
	bne	$t4, 98, color_bw	# 'b' Toggle drawing graph with grayscale bands
	xori	$s2, $s2, 1
	j	end_modifications
	
	color_bw:
	bne	$t4, 109, set_type	# 'm' Toggle drawing graph with color
	xori	$s3, $s3, 1
	j	end_modifications
	
	set_type:			# `t` Toggle between corresponding Mandelbrot and Julia Sets
	bne	$t4, 116, set_noncandidate
	xori	$s1, $s1, 1
	j	end_modifications
	
	set_noncandidate:
	bne	$t4, 99, set_graph	# `c` Set the Julia Set's Non-Candidate Value
	la	$t4, noncandidate_value
	li	$v0, 52
	la	$a0, noncandidate_real_msg
	syscall
	bne	$a1, -1, valid_nc_real
	li	$v0, 55
	la	$a0, input_error_msg
	li	$a1, 0
	syscall
	j 	main
	valid_nc_real:
	bne 	$0, $a1, nc_complex
	swc1	$f0, 0($t4)
	nc_complex:
	li	$v0, 52
	la	$a0, noncandidate_complex_msg
	syscall
	bne	$a1, -1, valid_nc_complex
	li	$v0, 55
	la	$a0, input_error_msg
	li	$a1, 0
	syscall
	j 	main
	valid_nc_complex:
	bne 	$0, $a1, end_modifications
	swc1	$f0, 4($t4)
	j	end_modifications
	
	set_graph:
	bne	$t4, 102, end_modifications	# 'f' Set graph parameters (Mandelbrot or Julia, frame bounds)
	la	$t4, real_min
	li	$v0, 52
	la	$a0, real_min_msg
	syscall
	bne	$a1, -1, valid_real_min
	li	$v0, 55
	la	$a0, input_error_msg
	li	$a1, 0
	syscall
	j 	main
	valid_real_min:
	bne 	$0, $a1, set_real_max
	swc1	$f0, 0($t4)
	
	set_real_max:
	la	$t4, real_max
	li	$v0, 52
	la	$a0, real_max_msg
	syscall
	bne	$a1, -1, valid_real_max
	li	$v0, 55
	la	$a0, input_error_msg
	li	$a1, 0
	syscall
	j 	main
	valid_real_max:
	bne 	$0, $a1, set_complex_min
	swc1	$f0, 0($t4)
	
	set_complex_min:
	la	$t4, complex_min
	li	$v0, 52
	la	$a0, complex_min_msg
	syscall
	bne	$a1, -1, valid_complex_min
	li	$v0, 55
	la	$a0, input_error_msg
	li	$a1, 0
	syscall
	j 	main
	valid_complex_min:
	bne 	$0, $a1, set_complex_max
	swc1	$f0, 0($t4)
	
	set_complex_max:
	la	$t4, complex_max
	li	$v0, 52
	la	$a0, complex_max_msg
	syscall
	bne	$a1, -1, valid_complex_max
	li	$v0, 55
	la	$a0, input_error_msg
	li	$a1, 0
	syscall
	j 	main
	valid_complex_max:
	bne 	$0, $a1, end_modifications
	swc1	$f0, 0($t4)
	
	
	end_modifications:
	jr $ra


#Name: Clear Screen
#Parameters: None
#Modifies: Bitmap, t0-2
#Returns: None
clear_screen:
	li 	$t0, BASE_BITMAP_ADDRESS
	li 	$t1, PIXEL_SIDE
	li	$t2, 0x000000FF
	mul 	$t1, $t1, $t1
	sll	$t1, $t1, 2
	add	$t1, $t1, $t0

	clear_loop:
	beq	$t0, $t1, after_clear_loop
	sw	$t2, ($t0)
	addiu	$t0, $t0, 4
	j	clear_loop
	
	after_clear_loop:
	jr	$ra
