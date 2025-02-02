package math_big

/*
	Copyright 2021 Jeroen van Rijn <nom@duclavier.com>.
	Made available under Odin's BSD-3 license.

	An arbitrary precision mathematics implementation in Odin.
	For the theoretical underpinnings, see Knuth's The Art of Computer Programming, Volume 2, section 4.3.
	The code started out as an idiomatic source port of libTomMath, which is in the public domain, with thanks.

	=============================    Private procedures    =============================

	Private procedures used by the above low-level routines follow.

	Don't call these yourself unless you really know what you're doing.
	They include implementations that are optimimal for certain ranges of input only.

	These aren't exported for the same reasons.
*/

import "core:intrinsics"
import "core:mem"

/*
	Multiplies |a| * |b| and only computes upto digs digits of result.
	HAC pp. 595, Algorithm 14.12  Modified so you can control how
	many digits of output are created.
*/
_private_int_mul :: proc(dest, a, b: ^Int, digits: int, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator;

	/*
		Can we use the fast multiplier?
	*/
	if digits < _WARRAY && min(a.used, b.used) < _MAX_COMBA {
		return #force_inline _private_int_mul_comba(dest, a, b, digits);
	}

	/*
		Set up temporary output `Int`, which we'll swap for `dest` when done.
	*/

	t := &Int{};

	internal_grow(t, max(digits, _DEFAULT_DIGIT_COUNT)) or_return;
	t.used = digits;

	/*
		Compute the digits of the product directly.
	*/
	pa := a.used;
	for ix := 0; ix < pa; ix += 1 {
		/*
			Limit ourselves to `digits` DIGITs of output.
		*/
		pb    := min(b.used, digits - ix);
		carry := _WORD(0);
		iy    := 0;

		/*
			Compute the column of the output and propagate the carry.
		*/
		#no_bounds_check for iy = 0; iy < pb; iy += 1 {
			/*
				Compute the column as a _WORD.
			*/
			column := _WORD(t.digit[ix + iy]) + _WORD(a.digit[ix]) * _WORD(b.digit[iy]) + carry;

			/*
				The new column is the lower part of the result.
			*/
			t.digit[ix + iy] = DIGIT(column & _WORD(_MASK));

			/*
				Get the carry word from the result.
			*/
			carry = column >> _DIGIT_BITS;
		}
		/*
			Set carry if it is placed below digits
		*/
		if ix + iy < digits {
			t.digit[ix + pb] = DIGIT(carry);
		}
	}

	internal_swap(dest, t);
	internal_destroy(t);
	return internal_clamp(dest);
}


/*
	Multiplication using the Toom-Cook 3-way algorithm.

	Much more complicated than Karatsuba but has a lower asymptotic running time of O(N**1.464).
	This algorithm is only particularly useful on VERY large inputs.
	(We're talking 1000s of digits here...).

	This file contains code from J. Arndt's book  "Matters Computational"
	and the accompanying FXT-library with permission of the author.

	Setup from:
		Chung, Jaewook, and M. Anwar Hasan. "Asymmetric squaring formulae."
		18th IEEE Symposium on Computer Arithmetic (ARITH'07). IEEE, 2007.

	The interpolation from above needed one temporary variable more than the interpolation here:

		Bodrato, Marco, and Alberto Zanoni. "What about Toom-Cook matrices optimality."
		Centro Vito Volterra Universita di Roma Tor Vergata (2006)
*/
_private_int_mul_toom :: proc(dest, a, b: ^Int, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator;

	S1, S2, T1, a0, a1, a2, b0, b1, b2 := &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{};
	defer destroy(S1, S2, T1, a0, a1, a2, b0, b1, b2);

	/*
		Init temps.
	*/
	internal_init_multi(S1, S2, T1)             or_return;

	/*
		B
	*/
	B := min(a.used, b.used) / 3;

	/*
		a = a2 * x^2 + a1 * x + a0;
	*/
	internal_grow(a0, B)                        or_return;
	internal_grow(a1, B)                        or_return;
	internal_grow(a2, a.used - 2 * B)           or_return;

	a0.used, a1.used = B, B;
	a2.used = a.used - 2 * B;

	internal_copy_digits(a0, a, a0.used)        or_return;
	internal_copy_digits(a1, a, a1.used, B)     or_return;
	internal_copy_digits(a2, a, a2.used, 2 * B) or_return;

	internal_clamp(a0);
	internal_clamp(a1);
	internal_clamp(a2);

	/*
		b = b2 * x^2 + b1 * x + b0;
	*/
	internal_grow(b0, B)                        or_return;
	internal_grow(b1, B)                        or_return;
	internal_grow(b2, b.used - 2 * B)           or_return;

	b0.used, b1.used = B, B;
	b2.used = b.used - 2 * B;

	internal_copy_digits(b0, b, b0.used)        or_return;
	internal_copy_digits(b1, b, b1.used, B)     or_return;
	internal_copy_digits(b2, b, b2.used, 2 * B) or_return;

	internal_clamp(b0);
	internal_clamp(b1);
	internal_clamp(b2);


	/*
		\\ S1 = (a2+a1+a0) * (b2+b1+b0);
	*/
	internal_add(T1, a2, a1)                    or_return; /*   T1 = a2 + a1; */
	internal_add(S2, T1, a0)                    or_return; /*   S2 = T1 + a0; */
	internal_add(dest, b2, b1)                  or_return; /* dest = b2 + b1; */
	internal_add(S1, dest, b0)                  or_return; /*   S1 =  c + b0; */
	internal_mul(S1, S1, S2)                    or_return; /*   S1 = S1 * S2; */

	/*
		\\S2 = (4*a2+2*a1+a0) * (4*b2+2*b1+b0);
	*/
	internal_add(T1, T1, a2)                    or_return; /*   T1 = T1 + a2; */
	internal_int_shl1(T1, T1)                   or_return; /*   T1 = T1 << 1; */
	internal_add(T1, T1, a0)                    or_return; /*   T1 = T1 + a0; */
	internal_add(dest, dest, b2)                or_return; /*    c =  c + b2; */
	internal_int_shl1(dest, dest)               or_return; /*    c =  c << 1; */
	internal_add(dest, dest, b0)                or_return; /*    c =  c + b0; */
	internal_mul(S2, T1, dest)                  or_return; /*   S2 = T1 *  c; */

	/*
		\\S3 = (a2-a1+a0) * (b2-b1+b0);
	*/
	internal_sub(a1, a2, a1)                    or_return; /*   a1 = a2 - a1; */
	internal_add(a1, a1, a0)                    or_return; /*   a1 = a1 + a0; */
	internal_sub(b1, b2, b1)                    or_return; /*   b1 = b2 - b1; */
	internal_add(b1, b1, b0)                    or_return; /*   b1 = b1 + b0; */
	internal_mul(a1, a1, b1)                    or_return; /*   a1 = a1 * b1; */
	internal_mul(b1, a2, b2)                    or_return; /*   b1 = a2 * b2; */

	/*
		\\S2 = (S2 - S3) / 3;
	*/
	internal_sub(S2, S2, a1)                    or_return; /*   S2 = S2 - a1; */
	_private_int_div_3(S2, S2)                  or_return; /*   S2 = S2 / 3; \\ this is an exact division  */
	internal_sub(a1, S1, a1)                    or_return; /*   a1 = S1 - a1; */
	internal_int_shr1(a1, a1)                   or_return; /*   a1 = a1 >> 1; */
	internal_mul(a0, a0, b0)                    or_return; /*   a0 = a0 * b0; */
	internal_sub(S1, S1, a0)                    or_return; /*   S1 = S1 - a0; */
	internal_sub(S2, S2, S1)                    or_return; /*   S2 = S2 - S1; */
	internal_int_shr1(S2, S2)                   or_return; /*   S2 = S2 >> 1; */
	internal_sub(S1, S1, a1)                    or_return; /*   S1 = S1 - a1; */
	internal_sub(S1, S1, b1)                    or_return; /*   S1 = S1 - b1; */
	internal_int_shl1(T1, b1)                   or_return; /*   T1 = b1 << 1; */
	internal_sub(S2, S2, T1)                    or_return; /*   S2 = S2 - T1; */
	internal_sub(a1, a1, S2)                    or_return; /*   a1 = a1 - S2; */

	/*
		P = b1*x^4+ S2*x^3+ S1*x^2+ a1*x + a0;
	*/
	internal_shl_digit(b1, 4 * B)               or_return;
	internal_shl_digit(S2, 3 * B)               or_return;
	internal_add(b1, b1, S2)                    or_return;
	internal_shl_digit(S1, 2 * B)               or_return;
	internal_add(b1, b1, S1)                    or_return;
	internal_shl_digit(a1, 1 * B)               or_return;
	internal_add(b1, b1, a1)                    or_return;
	internal_add(dest, b1, a0)                  or_return;

	/*
		a * b - P
	*/
	return nil;
}

/*
	product = |a| * |b| using Karatsuba Multiplication using three half size multiplications.

	Let `B` represent the radix [e.g. 2**_DIGIT_BITS] and let `n` represent
	half of the number of digits in the min(a,b)

	`a` = `a1` * `B`**`n` + `a0`
	`b` = `b`1 * `B`**`n` + `b0`

	Then, a * b => 1b1 * B**2n + ((a1 + a0)(b1 + b0) - (a0b0 + a1b1)) * B + a0b0

	Note that a1b1 and a0b0 are used twice and only need to be computed once.
	So in total three half size (half # of digit) multiplications are performed,
		a0b0, a1b1 and (a1+b1)(a0+b0)

	Note that a multiplication of half the digits requires 1/4th the number of
	single precision multiplications, so in total after one call 25% of the
	single precision multiplications are saved.

	Note also that the call to `internal_mul` can end up back in this function
	if the a0, a1, b0, or b1 are above the threshold.

	This is known as divide-and-conquer and leads to the famous O(N**lg(3)) or O(N**1.584)
	work which is asymptopically lower than the standard O(N**2) that the
	baseline/comba methods use. Generally though, the overhead of this method doesn't pay off
	until a certain size is reached, of around 80 used DIGITs.
*/
_private_int_mul_karatsuba :: proc(dest, a, b: ^Int, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator;

	x0, x1, y0, y1, t1, x0y0, x1y1 := &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{};
	defer destroy(x0, x1, y0, y1, t1, x0y0, x1y1);

	/*
		min # of digits, divided by two.
	*/
	B := min(a.used, b.used) >> 1;

	/*
		Init all the temps.
	*/
	internal_grow(x0, B)          or_return;
	internal_grow(x1, a.used - B) or_return;
	internal_grow(y0, B)          or_return;
	internal_grow(y1, b.used - B) or_return;
	internal_grow(t1, B * 2)      or_return;
	internal_grow(x0y0, B * 2)    or_return;
	internal_grow(x1y1, B * 2)    or_return;

	/*
		Now shift the digits.
	*/
	x0.used, y0.used = B, B;
	x1.used = a.used - B;
	y1.used = b.used - B;

	/*
		We copy the digits directly instead of using higher level functions
		since we also need to shift the digits.
	*/
	internal_copy_digits(x0, a, x0.used);
	internal_copy_digits(y0, b, y0.used);
	internal_copy_digits(x1, a, x1.used, B);
	internal_copy_digits(y1, b, y1.used, B);

	/*
		Only need to clamp the lower words since by definition the
		upper words x1/y1 must have a known number of digits.
	*/
	clamp(x0);
	clamp(y0);

	/*
		Now calc the products x0y0 and x1y1,
		after this x0 is no longer required, free temp [x0==t2]!
	*/
	internal_mul(x0y0, x0, y0)      or_return; /* x0y0 = x0*y0 */
	internal_mul(x1y1, x1, y1)      or_return; /* x1y1 = x1*y1 */
	internal_add(t1,   x1, x0)      or_return; /* now calc x1+x0 and */
	internal_add(x0,   y1, y0)      or_return; /* t2 = y1 + y0 */
	internal_mul(t1,   t1, x0)      or_return; /* t1 = (x1 + x0) * (y1 + y0) */

	/*
		Add x0y0.
	*/
	internal_add(x0, x0y0, x1y1)    or_return; /* t2 = x0y0 + x1y1 */
	internal_sub(t1,   t1,   x0)    or_return; /* t1 = (x1+x0)*(y1+y0) - (x1y1 + x0y0) */

	/*
		shift by B.
	*/
	internal_shl_digit(t1, B)       or_return; /* t1 = (x0y0 + x1y1 - (x1-x0)*(y1-y0))<<B */
	internal_shl_digit(x1y1, B * 2) or_return; /* x1y1 = x1y1 << 2*B */

	internal_add(t1, x0y0, t1)      or_return; /* t1 = x0y0 + t1 */
	internal_add(dest, t1, x1y1)    or_return; /* t1 = x0y0 + t1 + x1y1 */

	return nil;
}



/*
	Fast (comba) multiplier

	This is the fast column-array [comba] multiplier.  It is
	designed to compute the columns of the product first
	then handle the carries afterwards.  This has the effect
	of making the nested loops that compute the columns very
	simple and schedulable on super-scalar processors.

	This has been modified to produce a variable number of
	digits of output so if say only a half-product is required
	you don't have to compute the upper half (a feature
	required for fast Barrett reduction).

	Based on Algorithm 14.12 on pp.595 of HAC.
*/
_private_int_mul_comba :: proc(dest, a, b: ^Int, digits: int, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator;

	/*
		Set up array.
	*/
	W: [_WARRAY]DIGIT = ---;

	/*
		Grow the destination as required.
	*/
	internal_grow(dest, digits) or_return;

	/*
		Number of output digits to produce.
	*/
	pa := min(digits, a.used + b.used);

	/*
		Clear the carry
	*/
	_W := _WORD(0);

	ix: int;
	for ix = 0; ix < pa; ix += 1 {
		tx, ty, iy, iz: int;

		/*
			Get offsets into the two bignums.
		*/
		ty = min(b.used - 1, ix);
		tx = ix - ty;

		/*
			This is the number of times the loop will iterate, essentially.
			while (tx++ < a->used && ty-- >= 0) { ... }
		*/
		 
		iy = min(a.used - tx, ty + 1);

		/*
			Execute loop.
		*/
		#no_bounds_check for iz = 0; iz < iy; iz += 1 {
			_W += _WORD(a.digit[tx + iz]) * _WORD(b.digit[ty - iz]);
		}

		/*
			Store term.
		*/
		W[ix] = DIGIT(_W) & _MASK;

		/*
			Make next carry.
		*/
		_W = _W >> _WORD(_DIGIT_BITS);
	}

	/*
		Setup dest.
	*/
	old_used := dest.used;
	dest.used = pa;

	/*
		Now extract the previous digit [below the carry].
	*/
	copy_slice(dest.digit[0:], W[:pa]);	

	/*
		Clear unused digits [that existed in the old copy of dest].
	*/
	internal_zero_unused(dest, old_used);

	/*
		Adjust dest.used based on leading zeroes.
	*/

	return internal_clamp(dest);
}

/*
	Low level squaring, b = a*a, HAC pp.596-597, Algorithm 14.16
	Assumes `dest` and `src` to not be `nil`, and `src` to have been initialized.
*/
_private_int_sqr :: proc(dest, src: ^Int, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator;
	pa := src.used;

	t := &Int{}; ix, iy: int;
	/*
		Grow `t` to maximum needed size, or `_DEFAULT_DIGIT_COUNT`, whichever is bigger.
	*/
	internal_grow(t, max((2 * pa) + 1, _DEFAULT_DIGIT_COUNT)) or_return;
	t.used = (2 * pa) + 1;

	#no_bounds_check for ix = 0; ix < pa; ix += 1 {
		carry := DIGIT(0);
		/*
			First calculate the digit at 2*ix; calculate double precision result.
		*/
		r := _WORD(t.digit[ix+ix]) + (_WORD(src.digit[ix]) * _WORD(src.digit[ix]));

		/*
			Store lower part in result.
		*/
		t.digit[ix+ix] = DIGIT(r & _WORD(_MASK));
		/*
			Get the carry.
		*/
		carry = DIGIT(r >> _DIGIT_BITS);

		#no_bounds_check for iy = ix + 1; iy < pa; iy += 1 {
			/*
				First calculate the product.
			*/
			r = _WORD(src.digit[ix]) * _WORD(src.digit[iy]);

			/* Now calculate the double precision result. Nóte we use
			 * addition instead of *2 since it's easier to optimize
			 */
			r = _WORD(t.digit[ix+iy]) + r + r + _WORD(carry);

			/*
				Store lower part.
			*/
			t.digit[ix+iy] = DIGIT(r & _WORD(_MASK));

			/*
				Get carry.
			*/
			carry = DIGIT(r >> _DIGIT_BITS);
		}
		/*
			Propagate upwards.
		*/
		#no_bounds_check for carry != 0 {
			r     = _WORD(t.digit[ix+iy]) + _WORD(carry);
			t.digit[ix+iy] = DIGIT(r & _WORD(_MASK));
			carry = DIGIT(r >> _WORD(_DIGIT_BITS));
			iy += 1;
		}
	}

	err = internal_clamp(t);
	internal_swap(dest, t);
	internal_destroy(t);
	return err;
}

/*
	The jist of squaring...
	You do like mult except the offset of the tmpx [one that starts closer to zero] can't equal the offset of tmpy.
	So basically you set up iy like before then you min it with (ty-tx) so that it never happens.
	You double all those you add in the inner loop. After that loop you do the squares and add them in.

	Assumes `dest` and `src` not to be `nil` and `src` to have been initialized.	
*/
_private_int_sqr_comba :: proc(dest, src: ^Int, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator;

	W: [_WARRAY]DIGIT = ---;

	/*
		Grow the destination as required.
	*/
	pa := uint(src.used) + uint(src.used);
	internal_grow(dest, int(pa)) or_return;

	/*
		Number of output digits to produce.
	*/
	W1 := _WORD(0);
	_W  : _WORD = ---;
	ix := uint(0);

	#no_bounds_check for ; ix < pa; ix += 1 {
		/*
			Clear counter.
		*/
		_W = {};

		/*
			Get offsets into the two bignums.
		*/
		ty := min(uint(src.used) - 1, ix);
		tx := ix - ty;

		/*
			This is the number of times the loop will iterate,
			essentially while (tx++ < a->used && ty-- >= 0) { ... }
		*/
		iy := min(uint(src.used) - tx, ty + 1);

		/*
			Now for squaring, tx can never equal ty.
			We halve the distance since they approach at a rate of 2x,
			and we have to round because odd cases need to be executed.
		*/
		iy = min(iy, ((ty - tx) + 1) >> 1 );

		/*
			Execute loop.
		*/
		#no_bounds_check for iz := uint(0); iz < iy; iz += 1 {
			_W += _WORD(src.digit[tx + iz]) * _WORD(src.digit[ty - iz]);
		}

		/*
			Double the inner product and add carry.
		*/
		_W = _W + _W + W1;

		/*
			Even columns have the square term in them.
		*/
		if ix & 1 == 0 {
			_W += _WORD(src.digit[ix >> 1]) * _WORD(src.digit[ix >> 1]);
		}

		/*
			Store it.
		*/
		W[ix] = DIGIT(_W & _WORD(_MASK));

		/*
			Make next carry.
		*/
		W1 = _W >> _DIGIT_BITS;
	}

	/*
		Setup dest.
	*/
	old_used := dest.used;
	dest.used = src.used + src.used;

	#no_bounds_check for ix = 0; ix < pa; ix += 1 {
		dest.digit[ix] = W[ix] & _MASK;
	}

	/*
		Clear unused digits [that existed in the old copy of dest].
	*/
	internal_zero_unused(dest, old_used);

	return internal_clamp(dest);
}

/*
	Karatsuba squaring, computes `dest` = `src` * `src` using three half-size squarings.
 
 	See comments of `_private_int_mul_karatsuba` for details.
 	It is essentially the same algorithm but merely tuned to perform recursive squarings.
*/
_private_int_sqr_karatsuba :: proc(dest, src: ^Int, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator;

	x0, x1, t1, t2, x0x0, x1x1 := &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{};
	defer internal_destroy(x0, x1, t1, t2, x0x0, x1x1);

	/*
		Min # of digits, divided by two.
	*/
	B := src.used >> 1;

	/*
		Init temps.
	*/
	internal_grow(x0,   B) or_return;
	internal_grow(x1,   src.used - B) or_return;
	internal_grow(t1,   src.used * 2) or_return;
	internal_grow(t2,   src.used * 2) or_return;
	internal_grow(x0x0, B * 2       ) or_return;
	internal_grow(x1x1, (src.used - B) * 2) or_return;

	/*
		Now shift the digits.
	*/
	x0.used = B;
	x1.used = src.used - B;

	#force_inline internal_copy_digits(x0, src, x0.used);
	#force_inline mem.copy_non_overlapping(&x1.digit[0], &src.digit[B], size_of(DIGIT) * x1.used);
	#force_inline internal_clamp(x0);

	/*
		Now calc the products x0*x0 and x1*x1.
	*/
	internal_sqr(x0x0, x0) or_return;
	internal_sqr(x1x1, x1) or_return;

	/*
		Now calc (x1+x0)^2
	*/
	internal_add(t1, x0, x1) or_return;
	internal_sqr(t1, t1) or_return;

	/*
		Add x0y0
	*/
	internal_add(t2, x0x0, x1x1) or_return;
	internal_sub(t1, t1, t2) or_return;

	/*
		Shift by B.
	*/
	internal_shl_digit(t1, B) or_return;
	internal_shl_digit(x1x1, B * 2) or_return;
	internal_add(t1, t1, x0x0) or_return;
	internal_add(dest, t1, x1x1) or_return;

	return #force_inline internal_clamp(dest);
}

/*
	Squaring using Toom-Cook 3-way algorithm.

	Setup and interpolation from algorithm SQR_3 in Chung, Jaewook, and M. Anwar Hasan. "Asymmetric squaring formulae."
	  18th IEEE Symposium on Computer Arithmetic (ARITH'07). IEEE, 2007.
*/
_private_int_sqr_toom :: proc(dest, src: ^Int, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator;

	S0, a0, a1, a2 := &Int{}, &Int{}, &Int{}, &Int{};
	defer internal_destroy(S0, a0, a1, a2);

	/*
		Init temps.
	*/
	internal_zero(S0) or_return;

	/*
		B
	*/
	B := src.used / 3;

	/*
		a = a2 * x^2 + a1 * x + a0;
	*/
	internal_grow(a0, B) or_return;
	internal_grow(a1, B) or_return;
	internal_grow(a2, src.used - (2 * B)) or_return;

	a0.used = B;
	a1.used = B;
	a2.used = src.used - 2 * B;

	#force_inline mem.copy_non_overlapping(&a0.digit[0], &src.digit[    0], size_of(DIGIT) * a0.used);
	#force_inline mem.copy_non_overlapping(&a1.digit[0], &src.digit[    B], size_of(DIGIT) * a1.used);
	#force_inline mem.copy_non_overlapping(&a2.digit[0], &src.digit[2 * B], size_of(DIGIT) * a2.used);

	internal_clamp(a0);
	internal_clamp(a1);
	internal_clamp(a2);

	/** S0 = a0^2;  */
	internal_sqr(S0, a0) or_return;

	/** \\S1 = (a2 + a1 + a0)^2 */
	/** \\S2 = (a2 - a1 + a0)^2  */
	/** \\S1 = a0 + a2; */
	/** a0 = a0 + a2; */
	internal_add(a0, a0, a2) or_return;
	/** \\S2 = S1 - a1; */
	/** b = a0 - a1; */
	internal_sub(dest, a0, a1) or_return;
	/** \\S1 = S1 + a1; */
	/** a0 = a0 + a1; */
	internal_add(a0, a0, a1) or_return;
	/** \\S1 = S1^2;  */
	/** a0 = a0^2; */
	internal_sqr(a0, a0) or_return;
	/** \\S2 = S2^2;  */
	/** b = b^2; */
	internal_sqr(dest, dest) or_return;
	/** \\ S3 = 2 * a1 * a2  */
	/** \\S3 = a1 * a2;  */
	/** a1 = a1 * a2; */
	internal_mul(a1, a1, a2) or_return;
	/** \\S3 = S3 << 1;  */
	/** a1 = a1 << 1; */
	internal_shl(a1, a1, 1) or_return;
	/** \\S4 = a2^2;  */
	/** a2 = a2^2; */
	internal_sqr(a2, a2) or_return;
	/** \\ tmp = (S1 + S2)/2  */
	/** \\tmp = S1 + S2; */
	/** b = a0 + b; */
	internal_add(dest, a0, dest) or_return;
	/** \\tmp = tmp >> 1; */
	/** b = b >> 1; */
	internal_shr(dest, dest, 1) or_return;
	/** \\ S1 = S1 - tmp - S3  */
	/** \\S1 = S1 - tmp; */
	/** a0 = a0 - b; */
	internal_sub(a0, a0, dest) or_return;
	/** \\S1 = S1 - S3;  */
	/** a0 = a0 - a1; */
	internal_sub(a0, a0, a1) or_return;
	/** \\S2 = tmp - S4 -S0  */
	/** \\S2 = tmp - S4;  */
	/** b = b - a2; */
	internal_sub(dest, dest, a2) or_return;
	/** \\S2 = S2 - S0;  */
	/** b = b - S0; */
	internal_sub(dest, dest, S0) or_return;
	/** \\P = S4*x^4 + S3*x^3 + S2*x^2 + S1*x + S0; */
	/** P = a2*x^4 + a1*x^3 + b*x^2 + a0*x + S0; */
	internal_shl_digit(  a2, 4 * B) or_return;
	internal_shl_digit(  a1, 3 * B) or_return;
	internal_shl_digit(dest, 2 * B) or_return;
	internal_shl_digit(  a0, 1 * B) or_return;

	internal_add(a2, a2, a1) or_return;
	internal_add(dest, dest, a2) or_return;
	internal_add(dest, dest, a0) or_return;
	internal_add(dest, dest, S0) or_return;
	/** a^2 - P  */

	return #force_inline internal_clamp(dest);
}

/*
	Divide by three (based on routine from MPI and the GMP manual).
*/
_private_int_div_3 :: proc(quotient, numerator: ^Int, allocator := context.allocator) -> (remainder: DIGIT, err: Error) {
	context.allocator = allocator;

	/*
		b = 2^_DIGIT_BITS / 3
	*/
 	b := _WORD(1) << _WORD(_DIGIT_BITS) / _WORD(3);

	q := &Int{};
	internal_grow(q, numerator.used) or_return;
	q.used = numerator.used;
	q.sign = numerator.sign;

	w, t: _WORD;
	#no_bounds_check for ix := numerator.used; ix >= 0; ix -= 1 {
		w = (w << _WORD(_DIGIT_BITS)) | _WORD(numerator.digit[ix]);
		if w >= 3 {
			/*
				Multiply w by [1/3].
			*/
			t = (w * b) >> _WORD(_DIGIT_BITS);

			/*
				Now subtract 3 * [w/3] from w, to get the remainder.
			*/
			w -= t+t+t;

			/*
				Fixup the remainder as required since the optimization is not exact.
			*/
			for w >= 3 {
				t += 1;
				w -= 3;
			}
		} else {
			t = 0;
		}
		q.digit[ix] = DIGIT(t);
	}
	remainder = DIGIT(w);

	/*
		[optional] store the quotient.
	*/
	if quotient != nil {
		err = clamp(q);
 		internal_swap(q, quotient);
 	}
	internal_destroy(q);
	return remainder, nil;
}

/*
	Signed Integer Division

	c*b + d == a [i.e. a/b, c=quotient, d=remainder], HAC pp.598 Algorithm 14.20

	Note that the description in HAC is horribly incomplete.
	For example, it doesn't consider the case where digits are removed from 'x' in
	the inner loop.

	It also doesn't consider the case that y has fewer than three digits, etc.
	The overall algorithm is as described as 14.20 from HAC but fixed to treat these cases.
*/
_private_int_div_school :: proc(quotient, remainder, numerator, denominator: ^Int, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator;

	error_if_immutable(quotient, remainder) or_return;

	q, x, y, t1, t2 := &Int{}, &Int{}, &Int{}, &Int{}, &Int{};
	defer internal_destroy(q, x, y, t1, t2);

	internal_grow(q, numerator.used + 2) or_return;
	q.used = numerator.used + 2;

	internal_init_multi(t1, t2) or_return;
	internal_copy(x, numerator) or_return;
	internal_copy(y, denominator) or_return;

	/*
		Fix the sign.
	*/
	neg   := numerator.sign != denominator.sign;
	x.sign = .Zero_or_Positive;
	y.sign = .Zero_or_Positive;

	/*
		Normalize both x and y, ensure that y >= b/2, [b == 2**MP_DIGIT_BIT]
	*/
	norm := internal_count_bits(y) % _DIGIT_BITS;

	if norm < _DIGIT_BITS - 1 {
		norm = (_DIGIT_BITS - 1) - norm;
		internal_shl(x, x, norm) or_return;
		internal_shl(y, y, norm) or_return;
	} else {
		norm = 0;
	}

	/*
		Note: HAC does 0 based, so if used==5 then it's 0,1,2,3,4, i.e. use 4
	*/
	n := x.used - 1;
	t := y.used - 1;

	/*
		while (x >= y*b**n-t) do { q[n-t] += 1; x -= y*b**{n-t} }
		y = y*b**{n-t}
	*/

	internal_shl_digit(y, n - t) or_return;

	c := internal_cmp(x, y);
	for c != -1 {
		q.digit[n - t] += 1;
		internal_sub(x, x, y) or_return;
		c = internal_cmp(x, y);
	}

	/*
		Reset y by shifting it back down.
	*/
	internal_shr_digit(y, n - t);

	/*
		Step 3. for i from n down to (t + 1).
	*/
	#no_bounds_check for i := n; i >= (t + 1); i -= 1 {
		if (i > x.used) { continue; }

		/*
			step 3.1 if xi == yt then set q{i-t-1} to b-1, otherwise set q{i-t-1} to (xi*b + x{i-1})/yt
		*/
		if x.digit[i] == y.digit[t] {
			q.digit[(i - t) - 1] = 1 << (_DIGIT_BITS - 1);
		} else {

			tmp := _WORD(x.digit[i]) << _DIGIT_BITS;
			tmp |= _WORD(x.digit[i - 1]);
			tmp /= _WORD(y.digit[t]);
			if tmp > _WORD(_MASK) {
				tmp = _WORD(_MASK);
			}
			q.digit[(i - t) - 1] = DIGIT(tmp & _WORD(_MASK));
		}

		/* while (q{i-t-1} * (yt * b + y{t-1})) >
					xi * b**2 + xi-1 * b + xi-2

			do q{i-t-1} -= 1;
		*/

		iter := 0;

		q.digit[(i - t) - 1] = (q.digit[(i - t) - 1] + 1) & _MASK;
		#no_bounds_check for {
			q.digit[(i - t) - 1] = (q.digit[(i - t) - 1] - 1) & _MASK;

			/*
				Find left hand.
			*/
			internal_zero(t1);
			t1.digit[0] = ((t - 1) < 0) ? 0 : y.digit[t - 1];
			t1.digit[1] = y.digit[t];
			t1.used = 2;
			internal_mul(t1, t1, q.digit[(i - t) - 1]) or_return;

			/*
				Find right hand.
			*/
			t2.digit[0] = ((i - 2) < 0) ? 0 : x.digit[i - 2];
			t2.digit[1] = x.digit[i - 1]; /* i >= 1 always holds */
			t2.digit[2] = x.digit[i];
			t2.used = 3;

			if t1_t2 := internal_cmp_mag(t1, t2); t1_t2 != 1 {
				break;
			}
			iter += 1; if iter > 100 {
				return .Max_Iterations_Reached;
			}
		}

		/*
			Step 3.3 x = x - q{i-t-1} * y * b**{i-t-1}
		*/
		int_mul_digit(t1, y, q.digit[(i - t) - 1]) or_return;
		internal_shl_digit(t1, (i - t) - 1) or_return;
		internal_sub(x, x, t1) or_return;

		/*
			if x < 0 then { x = x + y*b**{i-t-1}; q{i-t-1} -= 1; }
		*/
		if x.sign == .Negative {
			internal_copy(t1, y) or_return;
			internal_shl_digit(t1, (i - t) - 1) or_return;
			internal_add(x, x, t1) or_return;

			q.digit[(i - t) - 1] = (q.digit[(i - t) - 1] - 1) & _MASK;
		}
	}

	/*
		Now q is the quotient and x is the remainder, [which we have to normalize]
		Get sign before writing to c.
	*/
	z, _ := is_zero(x);
	x.sign = .Zero_or_Positive if z else numerator.sign;

	if quotient != nil {
		internal_clamp(q);
		internal_swap(q, quotient);
		quotient.sign = .Negative if neg else .Zero_or_Positive;
	}

	if remainder != nil {
		internal_shr(x, x, norm) or_return;
		internal_swap(x, remainder);
	}

	return nil;
}

/*
	Direct implementation of algorithms 1.8 "RecursiveDivRem" and 1.9 "UnbalancedDivision" from:

		Brent, Richard P., and Paul Zimmermann. "Modern computer arithmetic"
		Vol. 18. Cambridge University Press, 2010
		Available online at https://arxiv.org/pdf/1004.4710

	pages 19ff. in the above online document.
*/
_private_div_recursion :: proc(quotient, remainder, a, b: ^Int, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator;

	A1, A2, B1, B0, Q1, Q0, R1, R0, t := &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{};
	defer internal_destroy(A1, A2, B1, B0, Q1, Q0, R1, R0, t);

	m := a.used - b.used;
	k := m / 2;

	if m < MUL_KARATSUBA_CUTOFF {
		return _private_int_div_school(quotient, remainder, a, b);
	}

	internal_init_multi(A1, A2, B1, B0, Q1, Q0, R1, R0, t) or_return;

	/*
		`B1` = `b` / `beta`^`k`, `B0` = `b` % `beta`^`k`
	*/
	internal_shrmod(B1, B0, b, k * _DIGIT_BITS) or_return;

	/*
		(Q1, R1) =  RecursiveDivRem(A / beta^(2k), B1)
	*/
	internal_shrmod(A1, t, a, 2 * k * _DIGIT_BITS) or_return;
	_private_div_recursion(Q1, R1, A1, B1) or_return;

	/*
		A1 = (R1 * beta^(2k)) + (A % beta^(2k)) - (Q1 * B0 * beta^k)
	*/
	internal_shl_digit(R1, 2 * k) or_return;
	internal_add(A1, R1, t) or_return;
	internal_mul(t, Q1, B0) or_return;

	/*
		While A1 < 0 do Q1 = Q1 - 1, A1 = A1 + (beta^k * B)
	*/
	if internal_cmp(A1, 0) == -1 {
		internal_shl(t, b, k * _DIGIT_BITS) or_return;

		for {
			internal_decr(Q1) or_return;
			internal_add(A1, A1, t) or_return;
			if internal_cmp(A1, 0) != -1 {
				break;
			}
		}
	}

	/*
		(Q0, R0) =  RecursiveDivRem(A1 / beta^(k), B1)
	*/
	internal_shrmod(A1, t, A1, k * _DIGIT_BITS) or_return;
	_private_div_recursion(Q0, R0, A1, B1) or_return;

	/*
		A2 = (R0*beta^k) +  (A1 % beta^k) - (Q0*B0)
	*/
	internal_shl_digit(R0, k) or_return;
	internal_add(A2, R0, t) or_return;
	internal_mul(t, Q0, B0) or_return;
	internal_sub(A2, A2, t) or_return;

	/*
		While A2 < 0 do Q0 = Q0 - 1, A2 = A2 + B.
	*/
	for internal_cmp(A2, 0) == -1 {
		internal_decr(Q0) or_return;
		internal_add(A2, A2, b) or_return;
	}

	/*
		Return q = (Q1*beta^k) + Q0, r = A2.
	*/
	internal_shl_digit(Q1, k) or_return;
	internal_add(quotient, Q1, Q0) or_return;

	return internal_copy(remainder, A2);
}

_private_int_div_recursive :: proc(quotient, remainder, a, b: ^Int, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator;

	A, B, Q, Q1, R, A_div, A_mod := &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{};
	defer internal_destroy(A, B, Q, Q1, R, A_div, A_mod);

	internal_init_multi(A, B, Q, Q1, R, A_div, A_mod) or_return;

	/*
		Most significant bit of a limb.
		Assumes  _DIGIT_MAX < (sizeof(DIGIT) * sizeof(u8)).
	*/
	msb := (_DIGIT_MAX + DIGIT(1)) >> 1;
	sigma := 0;
	msb_b := b.digit[b.used - 1];
	for msb_b < msb {
		sigma += 1;
		msb_b <<= 1;
	}

	/*
		Use that sigma to normalize B.
	*/
	internal_shl(B, b, sigma) or_return;
	internal_shl(A, a, sigma) or_return;

	/*
		Fix the sign.
	*/
	neg := a.sign != b.sign;
	A.sign = .Zero_or_Positive; B.sign = .Zero_or_Positive;

	/*
		If the magnitude of "A" is not more more than twice that of "B" we can work
		on them directly, otherwise we need to work at "A" in chunks.
	*/
	n := B.used;
	m := A.used - B.used;

	/*
		Q = 0. We already ensured that when we called `internal_init_multi`.
	*/
	for m > n {
		/*
			(q, r) = RecursiveDivRem(A / (beta^(m-n)), B)
		*/
		j := (m - n) * _DIGIT_BITS;
		internal_shrmod(A_div, A_mod, A, j) or_return;
		_private_div_recursion(Q1, R, A_div, B) or_return;

		/*
			Q = (Q*beta!(n)) + q
		*/
		internal_shl(Q, Q, n * _DIGIT_BITS) or_return;
		internal_add(Q, Q, Q1) or_return;

		/*
			A = (r * beta^(m-n)) + (A % beta^(m-n))
		*/
		internal_shl(R, R, (m - n) * _DIGIT_BITS) or_return;
		internal_add(A, R, A_mod) or_return;

		/*
			m = m - n
		*/
		m -= n;
	}

	/*
		(q, r) = RecursiveDivRem(A, B)
	*/
	_private_div_recursion(Q1, R, A, B) or_return;

	/*
		Q = (Q * beta^m) + q, R = r
	*/
	internal_shl(Q, Q, m * _DIGIT_BITS) or_return;
	internal_add(Q, Q, Q1) or_return;

	/*
		Get sign before writing to dest.
	*/
	R.sign = .Zero_or_Positive if internal_is_zero(Q) else a.sign;

	if quotient != nil {
		swap(quotient, Q);
		quotient.sign = .Negative if neg else .Zero_or_Positive;
	}
	if remainder != nil {
		/*
			De-normalize the remainder.
		*/
		internal_shrmod(R, nil, R, sigma) or_return;
		swap(remainder, R);
	}
	return nil;
}

/*
	Slower bit-bang division... also smaller.
*/
@(deprecated="Use `_int_div_school`, it's 3.5x faster.")
_private_int_div_small :: proc(quotient, remainder, numerator, denominator: ^Int) -> (err: Error) {

	ta, tb, tq, q := &Int{}, &Int{}, &Int{}, &Int{};
	c: int;
	defer destroy(ta, tb, tq, q);

	for {
		internal_one(tq) or_return;

		num_bits, _ := count_bits(numerator);
		den_bits, _ := count_bits(denominator);
		n := num_bits - den_bits;

		abs(ta, numerator)   or_return;
		abs(tb, denominator) or_return;
		shl(tb, tb, n)       or_return;
		shl(tq, tq, n)       or_return;

		for n >= 0 {
			if c, _ = cmp_mag(ta, tb); c == 0 || c == 1 {
				// ta -= tb
				sub(ta, ta, tb) or_return;
				//  q += tq
				add( q, q,  tq) or_return;
			}
			shr1(tb, tb) or_return;
			shr1(tq, tq) or_return;

			n -= 1;
		}

		/*
			Now q == quotient and ta == remainder.
		*/
		neg := numerator.sign != denominator.sign;
		if quotient != nil {
			swap(quotient, q);
			z, _ := is_zero(quotient);
			quotient.sign = .Negative if neg && !z else .Zero_or_Positive;
		}
		if remainder != nil {
			swap(remainder, ta);
			z, _ := is_zero(numerator);
			remainder.sign = .Zero_or_Positive if z else numerator.sign;
		}

		break;
	}
	return err;
}



/*
	Binary split factorial algo due to: http://www.luschny.de/math/factorial/binarysplitfact.html
*/
_private_int_factorial_binary_split :: proc(res: ^Int, n: int, allocator := context.allocator) -> (err: Error) {

	inner, outer, start, stop, temp := &Int{}, &Int{}, &Int{}, &Int{}, &Int{};
	defer internal_destroy(inner, outer, start, stop, temp);

	internal_one(inner, false, allocator) or_return;
	internal_one(outer, false, allocator) or_return;

	bits_used := int(_DIGIT_TYPE_BITS - intrinsics.count_leading_zeros(n));

	for i := bits_used; i >= 0; i -= 1 {
		start := (n >> (uint(i) + 1)) + 1 | 1;
		stop  := (n >> uint(i)) + 1 | 1;
		_private_int_recursive_product(temp, start, stop, 0, allocator) or_return;
		internal_mul(inner, inner, temp, allocator) or_return;
		internal_mul(outer, outer, inner, allocator) or_return;
	}
	shift := n - intrinsics.count_ones(n);

	return internal_shl(res, outer, int(shift), allocator);
}

/*
	Recursive product used by binary split factorial algorithm.
*/
_private_int_recursive_product :: proc(res: ^Int, start, stop: int, level := int(0), allocator := context.allocator) -> (err: Error) {
	t1, t2 := &Int{}, &Int{};
	defer internal_destroy(t1, t2);

	if level > FACTORIAL_BINARY_SPLIT_MAX_RECURSIONS {
		return .Max_Iterations_Reached;
	}

	num_factors := (stop - start) >> 1;
	if num_factors == 2 {
		internal_set(t1, start, false, allocator) or_return;
		when true {
			internal_grow(t2, t1.used + 1, false, allocator) or_return;
			internal_add(t2, t1, 2, allocator) or_return;
		} else {
			add(t2, t1, 2) or_return;
		}
		return internal_mul(res, t1, t2, allocator);
	}

	if num_factors > 1 {
		mid := (start + num_factors) | 1;
		_private_int_recursive_product(t1, start,  mid, level + 1, allocator) or_return;
		_private_int_recursive_product(t2,   mid, stop, level + 1, allocator) or_return;
		return internal_mul(res, t1, t2, allocator);
	}

	if num_factors == 1 {
		return #force_inline internal_set(res, start, true, allocator);
	}

	return #force_inline internal_one(res, true, allocator);
}

/*
	Internal function computing both GCD using the binary method,
		and, if target isn't `nil`, also LCM.

	Expects the `a` and `b` to have been initialized
		and one or both of `res_gcd` or `res_lcm` not to be `nil`.

	If both `a` and `b` are zero, return zero.
	If either `a` or `b`, return the other one.

	The `gcd` and `lcm` wrappers have already done this test,
	but `gcd_lcm` wouldn't have, so we still need to perform it.

	If neither result is wanted, we have nothing to do.
*/
_private_int_gcd_lcm :: proc(res_gcd, res_lcm, a, b: ^Int, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator;

	if res_gcd == nil && res_lcm == nil {
		return nil;
	}

	/*
		We need a temporary because `res_gcd` is allowed to be `nil`.
	*/
	if a.used == 0 && b.used == 0 {
		/*
			GCD(0, 0) and LCM(0, 0) are both 0.
		*/
		if res_gcd != nil {
			internal_zero(res_gcd) or_return;
		}
		if res_lcm != nil {
			internal_zero(res_lcm) or_return;
		}
		return nil;
	} else if a.used == 0 {
		/*
			We can early out with GCD = B and LCM = 0
		*/
		if res_gcd != nil {
			internal_abs(res_gcd, b) or_return;
		}
		if res_lcm != nil {
			internal_zero(res_lcm) or_return;
		}
		return nil;
	} else if b.used == 0 {
		/*
			We can early out with GCD = A and LCM = 0
		*/
		if res_gcd != nil {
			internal_abs(res_gcd, a) or_return;
		}
		if res_lcm != nil {
			internal_zero(res_lcm) or_return;
		}
		return nil;
	}

	temp_gcd_res := &Int{};
	defer internal_destroy(temp_gcd_res);

	/*
		If neither `a` or `b` was zero, we need to compute `gcd`.
 		Get copies of `a` and `b` we can modify.
 	*/
	u, v := &Int{}, &Int{};
	defer internal_destroy(u, v);
	internal_copy(u, a) or_return;
	internal_copy(v, b) or_return;

 	/*
 		Must be positive for the remainder of the algorithm.
 	*/
	u.sign = .Zero_or_Positive; v.sign = .Zero_or_Positive;

 	/*
 		B1.  Find the common power of two for `u` and `v`.
 	*/
 	u_lsb, _ := internal_count_lsb(u);
 	v_lsb, _ := internal_count_lsb(v);
 	k        := min(u_lsb, v_lsb);

	if k > 0 {
		/*
			Divide the power of two out.
		*/
		internal_shr(u, u, k) or_return;
		internal_shr(v, v, k) or_return;
	}

	/*
		Divide any remaining factors of two out.
	*/
	if u_lsb != k {
		internal_shr(u, u, u_lsb - k) or_return;
	}
	if v_lsb != k {
		internal_shr(v, v, v_lsb - k) or_return;
	}

	for v.used != 0 {
		/*
			Make sure `v` is the largest.
		*/
		if internal_cmp_mag(u, v) == 1 {
			/*
				Swap `u` and `v` to make sure `v` is >= `u`.
			*/
			internal_swap(u, v);
		}

		/*
			Subtract smallest from largest.
		*/
		internal_sub(v, v, u) or_return;

		/*
			Divide out all factors of two.
		*/
		b, _ := internal_count_lsb(v);
		internal_shr(v, v, b) or_return;
	}

 	/*
 		Multiply by 2**k which we divided out at the beginning.
 	*/
 	internal_shl(temp_gcd_res, u, k) or_return;
 	temp_gcd_res.sign = .Zero_or_Positive;

	/*
		We've computed `gcd`, either the long way, or because one of the inputs was zero.
		If we don't want `lcm`, we're done.
	*/
	if res_lcm == nil {
		internal_swap(temp_gcd_res, res_gcd);
		return nil;
	}

	/*
		Computes least common multiple as `|a*b|/gcd(a,b)`
		Divide the smallest by the GCD.
	*/
	if internal_cmp_mag(a, b) == -1 {
		/*
			Store quotient in `t2` such that `t2 * b` is the LCM.
		*/
		internal_div(res_lcm, a, temp_gcd_res) or_return;
		err = internal_mul(res_lcm, res_lcm, b);
	} else {
		/*
			Store quotient in `t2` such that `t2 * a` is the LCM.
		*/
		internal_div(res_lcm, a, temp_gcd_res) or_return;
		err = internal_mul(res_lcm, res_lcm, b);
	}

	if res_gcd != nil {
		internal_swap(temp_gcd_res, res_gcd);
	}

	/*
		Fix the sign to positive and return.
	*/
	res_lcm.sign = .Zero_or_Positive;
	return err;
}

/*
	Internal implementation of log.
	Assumes `a` not to be `nil` and to have been initialized.
*/
_private_int_log :: proc(a: ^Int, base: DIGIT, allocator := context.allocator) -> (res: int, err: Error) {
	bracket_low, bracket_high, bracket_mid, t, bi_base := &Int{}, &Int{}, &Int{}, &Int{}, &Int{};
	defer internal_destroy(bracket_low, bracket_high, bracket_mid, t, bi_base);

	ic := #force_inline internal_cmp(a, base);
	if ic == -1 || ic == 0 {
		return 1 if ic == 0 else 0, nil;
	}
	defer if err != nil {
		res = -1;
	}

	internal_set(bi_base, base, true, allocator)       or_return;
	internal_clear(bracket_mid, false, allocator)      or_return;
	internal_clear(t, false, allocator)                or_return;
	internal_one(bracket_low, false, allocator)        or_return;
	internal_set(bracket_high, base, false, allocator) or_return;

	low := 0; high := 1;

	/*
		A kind of Giant-step/baby-step algorithm.
		Idea shamelessly stolen from https://programmingpraxis.com/2010/05/07/integer-logarithms/2/
		The effect is asymptotic, hence needs benchmarks to test if the Giant-step should be skipped
		for small n.
	*/

	for {
		/*
			Iterate until `a` is bracketed between low + high.
		*/
		if #force_inline internal_cmp(bracket_high, a) != -1 {
			break;
		}

		low = high;
		#force_inline internal_copy(bracket_low, bracket_high) or_return;
		high <<= 1;
		#force_inline internal_sqr(bracket_high, bracket_high) or_return;
	}

	for (high - low) > 1 {
		mid := (high + low) >> 1;

		#force_inline internal_pow(t, bi_base, mid - low) or_return;

		#force_inline internal_mul(bracket_mid, bracket_low, t) or_return;

		mc := #force_inline internal_cmp(a, bracket_mid);
		switch mc {
		case -1:
			high = mid;
			internal_swap(bracket_mid, bracket_high);
		case  0:
			return mid, nil;
		case  1:
			low = mid;
			internal_swap(bracket_mid, bracket_low);
		}
	}

	fc := #force_inline internal_cmp(bracket_high, a);
	res = high if fc == 0 else low;

	return;
}




/*
	hac 14.61, pp608
*/
_private_inverse_modulo :: proc(dest, a, b: ^Int, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator;
	x, y, u, v, A, B, C, D := &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{};
	defer internal_destroy(x, y, u, v, A, B, C, D);

	/*
		`b` cannot be negative.
	*/
	if b.sign == .Negative || internal_is_zero(b) {
		return .Invalid_Argument;
	}

	/*
		init temps.
	*/
	internal_init_multi(x, y, u, v, A, B, C, D) or_return;

	/*
		`x` = `a` % `b`, `y` = `b`
	*/
	internal_mod(x, a, b) or_return;
	internal_copy(y, b) or_return;

	/*
		2. [modified] if x,y are both even then return an error!
	*/
	if internal_is_even(x) && internal_is_even(y) {
		return .Invalid_Argument;
	}

	/*
		3. u=x, v=y, A=1, B=0, C=0, D=1
	*/
	internal_copy(u, x) or_return;
	internal_copy(v, y) or_return;
	internal_one(A) or_return;
	internal_one(D) or_return;

	for {
		/*
			4.  while `u` is even do:
		*/
		for internal_is_even(u) {
			/*
				4.1 `u` = `u` / 2
			*/
			internal_int_shr1(u, u) or_return;

			/*
				4.2 if `A` or `B` is odd then:
			*/
			if internal_is_odd(A) || internal_is_odd(B) {
				/*
					`A` = (`A`+`y`) / 2, `B` = (`B`-`x`) / 2
				*/
				internal_add(A, A, y) or_return;
				internal_add(B, B, x) or_return;
			}
			/*
				`A` = `A` / 2, `B` = `B` / 2
			*/
			internal_int_shr1(A, A) or_return;
			internal_int_shr1(B, B) or_return;
		}

		/*
			5.  while `v` is even do:
		*/
		for internal_is_even(v) {
			/*
				5.1 `v` = `v` / 2
			*/
			internal_int_shr1(v, v) or_return;

			/*
				5.2 if `C` or `D` is odd then:
			*/
			if internal_is_odd(C) || internal_is_odd(D) {
				/*
					`C` = (`C`+`y`) / 2, `D` = (`D`-`x`) / 2
				*/
				internal_add(C, C, y) or_return;
				internal_add(D, D, x) or_return;
			}
			/*
				`C` = `C` / 2, `D` = `D` / 2
			*/
			internal_int_shr1(C, C) or_return;
			internal_int_shr1(D, D) or_return;
		}

		/*
			6.  if `u` >= `v` then:
		*/
		if internal_cmp(u, v) != -1 {
			/*
				`u` = `u` - `v`, `A` = `A` - `C`, `B` = `B` - `D`
			*/
			internal_sub(u, u, v) or_return;
			internal_sub(A, A, C) or_return;
			internal_sub(B, B, D) or_return;
		} else {
			/* v - v - u, C = C - A, D = D - B */
			internal_sub(v, v, u) or_return;
			internal_sub(C, C, A) or_return;
			internal_sub(D, D, B) or_return;
		}

		/*
			If not zero goto step 4
		*/
		if internal_is_zero(u) {
			break;
		}
	}

	/*
		Now `a` = `C`, `b` = `D`, `gcd` == `g`*`v`
	*/

	/*
		If `v` != `1` then there is no inverse.
	*/
	if internal_cmp(v, 1) != 0 {
		return .Invalid_Argument;
	}

	/*
		If its too low.
	*/
	if internal_cmp(C, 0) == -1 {
		internal_add(C, C, b) or_return;
	}

	/*
		Too big.
	*/
	if internal_cmp(C, 0) != -1 {
		internal_sub(C, C, b) or_return;
	}

	/*
		`C` is now the inverse.
	*/
	swap(dest, C);

	return;
}

/*
	Computes the modular inverse via binary extended Euclidean algorithm, that is `dest` = 1 / `a` mod `b`.

	Based on slow invmod except this is optimized for the case where `b` is odd,
	as per HAC Note 14.64 on pp. 610.
*/
_private_inverse_modulo_odd :: proc(dest, a, b: ^Int, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator;
	x, y, u, v, B, D := &Int{}, &Int{}, &Int{}, &Int{}, &Int{}, &Int{};
	defer internal_destroy(x, y, u, v, B, D);

	sign: Sign;

	/*
		2. [modified] `b` must be odd.
	*/
	if internal_is_even(b) { return .Invalid_Argument; }

	/*
		Init all our temps.
	*/
	internal_init_multi(x, y, u, v, B, D) or_return;

	/*
		`x` == modulus, `y` == value to invert.
	*/
	internal_copy(x, b) or_return;

	/*
		We need `y` = `|a|`.
	*/
	internal_mod(y, a, b) or_return;

	/*
		If one of `x`, `y` is zero return an error!
	*/
	if internal_is_zero(x) || internal_is_zero(y) { return .Invalid_Argument; }

	/*
		3. `u` = `x`, `v` = `y`, `A` = 1, `B` = 0, `C` = 0, `D` = 1
	*/
	internal_copy(u, x) or_return;
	internal_copy(v, y) or_return;

	internal_one(D) or_return;

	for {
		/*
			4.  while `u` is even do.
		*/
		for internal_is_even(u) {
			/*
				4.1 `u` = `u` / 2
			*/
			internal_int_shr1(u, u) or_return;

			/*
				4.2 if `B` is odd then:
			*/
			if internal_is_odd(B) {
				/*
					`B` = (`B` - `x`) / 2
				*/
				internal_sub(B, B, x) or_return;
			}

			/*
				`B` = `B` / 2
			*/
			internal_int_shr1(B, B) or_return;
		}

		/*
			5.  while `v` is even do:
		*/
		for internal_is_even(v) {
			/*
				5.1 `v` = `v` / 2
			*/
			internal_int_shr1(v, v) or_return;

			/*
				5.2 if `D` is odd then:
			*/
			if internal_is_odd(D) {
				/*
					`D` = (`D` - `x`) / 2
				*/
				internal_sub(D, D, x) or_return;
			}
			/*
				`D` = `D` / 2
			*/
			internal_int_shr1(D, D) or_return;
		}

		/*
			6.  if `u` >= `v` then:
		*/
		if internal_cmp(u, v) != -1 {
			/*
				`u` = `u` - `v`, `B` = `B` - `D`
			*/
			internal_sub(u, u, v) or_return;
			internal_sub(B, B, D) or_return;
		} else {
			/*
				`v` - `v` - `u`, `D` = `D` - `B`
			*/
			internal_sub(v, v, u) or_return;
			internal_sub(D, D, B) or_return;
		}

		/*
			If not zero goto step 4.
		*/
		if internal_is_zero(u) { break; }
	}

	/*
		Now `a` = C, `b` = D, gcd == g*v
	*/

	/*
		if `v` != 1 then there is no inverse
	*/
	if internal_cmp(v, 1) != 0 {
		return .Invalid_Argument;
	}

	/*
		`b` is now the inverse.
	*/
	sign = a.sign;
	for internal_int_is_negative(D) {
		internal_add(D, D, b) or_return;
	}

	/*
		Too big.
	*/
	for internal_cmp_mag(D, b) != -1 {
		internal_sub(D, D, b) or_return;
	}

	swap(dest, D);
	dest.sign = sign;
	return nil;
}


/*
	Returns the log2 of an `Int`.
	Assumes `a` not to be `nil` and to have been initialized.
	Also assumes `base` is a power of two.
*/
_private_log_power_of_two :: proc(a: ^Int, base: DIGIT) -> (log: int, err: Error) {
	base := base;
	y: int;
	for y = 0; base & 1 == 0; {
		y += 1;
		base >>= 1;
	}
	log = internal_count_bits(a);
	return (log - 1) / y, err;
}

/*
	Copies DIGITs from `src` to `dest`.
	Assumes `src` and `dest` to not be `nil` and have been initialized.
*/
_private_copy_digits :: proc(dest, src: ^Int, digits: int, offset := int(0)) -> (err: Error) {
	digits := digits;
	/*
		If dest == src, do nothing
	*/
	if dest == src {
		return nil;
	}

	digits = min(digits, len(src.digit), len(dest.digit));
	mem.copy_non_overlapping(&dest.digit[0], &src.digit[offset], size_of(DIGIT) * digits);
	return nil;
}

/*	
	========================    End of private procedures    =======================

	===============================  Private tables  ===============================

	Tables used by `internal_*` and `_*`.
*/

_private_prime_table := []DIGIT{
	0x0002, 0x0003, 0x0005, 0x0007, 0x000B, 0x000D, 0x0011, 0x0013,
	0x0017, 0x001D, 0x001F, 0x0025, 0x0029, 0x002B, 0x002F, 0x0035,
	0x003B, 0x003D, 0x0043, 0x0047, 0x0049, 0x004F, 0x0053, 0x0059,
	0x0061, 0x0065, 0x0067, 0x006B, 0x006D, 0x0071, 0x007F, 0x0083,
	0x0089, 0x008B, 0x0095, 0x0097, 0x009D, 0x00A3, 0x00A7, 0x00AD,
	0x00B3, 0x00B5, 0x00BF, 0x00C1, 0x00C5, 0x00C7, 0x00D3, 0x00DF,
	0x00E3, 0x00E5, 0x00E9, 0x00EF, 0x00F1, 0x00FB, 0x0101, 0x0107,
	0x010D, 0x010F, 0x0115, 0x0119, 0x011B, 0x0125, 0x0133, 0x0137,

	0x0139, 0x013D, 0x014B, 0x0151, 0x015B, 0x015D, 0x0161, 0x0167,
	0x016F, 0x0175, 0x017B, 0x017F, 0x0185, 0x018D, 0x0191, 0x0199,
	0x01A3, 0x01A5, 0x01AF, 0x01B1, 0x01B7, 0x01BB, 0x01C1, 0x01C9,
	0x01CD, 0x01CF, 0x01D3, 0x01DF, 0x01E7, 0x01EB, 0x01F3, 0x01F7,
	0x01FD, 0x0209, 0x020B, 0x021D, 0x0223, 0x022D, 0x0233, 0x0239,
	0x023B, 0x0241, 0x024B, 0x0251, 0x0257, 0x0259, 0x025F, 0x0265,
	0x0269, 0x026B, 0x0277, 0x0281, 0x0283, 0x0287, 0x028D, 0x0293,
	0x0295, 0x02A1, 0x02A5, 0x02AB, 0x02B3, 0x02BD, 0x02C5, 0x02CF,

	0x02D7, 0x02DD, 0x02E3, 0x02E7, 0x02EF, 0x02F5, 0x02F9, 0x0301,
	0x0305, 0x0313, 0x031D, 0x0329, 0x032B, 0x0335, 0x0337, 0x033B,
	0x033D, 0x0347, 0x0355, 0x0359, 0x035B, 0x035F, 0x036D, 0x0371,
	0x0373, 0x0377, 0x038B, 0x038F, 0x0397, 0x03A1, 0x03A9, 0x03AD,
	0x03B3, 0x03B9, 0x03C7, 0x03CB, 0x03D1, 0x03D7, 0x03DF, 0x03E5,
	0x03F1, 0x03F5, 0x03FB, 0x03FD, 0x0407, 0x0409, 0x040F, 0x0419,
	0x041B, 0x0425, 0x0427, 0x042D, 0x043F, 0x0443, 0x0445, 0x0449,
	0x044F, 0x0455, 0x045D, 0x0463, 0x0469, 0x047F, 0x0481, 0x048B,

	0x0493, 0x049D, 0x04A3, 0x04A9, 0x04B1, 0x04BD, 0x04C1, 0x04C7,
	0x04CD, 0x04CF, 0x04D5, 0x04E1, 0x04EB, 0x04FD, 0x04FF, 0x0503,
	0x0509, 0x050B, 0x0511, 0x0515, 0x0517, 0x051B, 0x0527, 0x0529,
	0x052F, 0x0551, 0x0557, 0x055D, 0x0565, 0x0577, 0x0581, 0x058F,
	0x0593, 0x0595, 0x0599, 0x059F, 0x05A7, 0x05AB, 0x05AD, 0x05B3,
	0x05BF, 0x05C9, 0x05CB, 0x05CF, 0x05D1, 0x05D5, 0x05DB, 0x05E7,
	0x05F3, 0x05FB, 0x0607, 0x060D, 0x0611, 0x0617, 0x061F, 0x0623,
	0x062B, 0x062F, 0x063D, 0x0641, 0x0647, 0x0649, 0x064D, 0x0653,
};

when MATH_BIG_FORCE_64_BIT || (!MATH_BIG_FORCE_32_BIT && size_of(rawptr) == 8) {
	_factorial_table := [35]_WORD{
/* f(00): */                                                     1,
/* f(01): */                                                     1,
/* f(02): */                                                     2,
/* f(03): */                                                     6,
/* f(04): */                                                    24,
/* f(05): */                                                   120,
/* f(06): */                                                   720,
/* f(07): */                                                 5_040,
/* f(08): */                                                40_320,
/* f(09): */                                               362_880,
/* f(10): */                                             3_628_800,
/* f(11): */                                            39_916_800,
/* f(12): */                                           479_001_600,
/* f(13): */                                         6_227_020_800,
/* f(14): */                                        87_178_291_200,
/* f(15): */                                     1_307_674_368_000,
/* f(16): */                                    20_922_789_888_000,
/* f(17): */                                   355_687_428_096_000,
/* f(18): */                                 6_402_373_705_728_000,
/* f(19): */                               121_645_100_408_832_000,
/* f(20): */                             2_432_902_008_176_640_000,
/* f(21): */                            51_090_942_171_709_440_000,
/* f(22): */                         1_124_000_727_777_607_680_000,
/* f(23): */                        25_852_016_738_884_976_640_000,
/* f(24): */                       620_448_401_733_239_439_360_000,
/* f(25): */                    15_511_210_043_330_985_984_000_000,
/* f(26): */                   403_291_461_126_605_635_584_000_000,
/* f(27): */                10_888_869_450_418_352_160_768_000_000,
/* f(28): */               304_888_344_611_713_860_501_504_000_000,
/* f(29): */             8_841_761_993_739_701_954_543_616_000_000,
/* f(30): */           265_252_859_812_191_058_636_308_480_000_000,
/* f(31): */         8_222_838_654_177_922_817_725_562_880_000_000,
/* f(32): */       263_130_836_933_693_530_167_218_012_160_000_000,
/* f(33): */     8_683_317_618_811_886_495_518_194_401_280_000_000,
/* f(34): */   295_232_799_039_604_140_847_618_609_643_520_000_000,
	};
} else {
	_factorial_table := [21]_WORD{
/* f(00): */                                                     1,
/* f(01): */                                                     1,
/* f(02): */                                                     2,
/* f(03): */                                                     6,
/* f(04): */                                                    24,
/* f(05): */                                                   120,
/* f(06): */                                                   720,
/* f(07): */                                                 5_040,
/* f(08): */                                                40_320,
/* f(09): */                                               362_880,
/* f(10): */                                             3_628_800,
/* f(11): */                                            39_916_800,
/* f(12): */                                           479_001_600,
/* f(13): */                                         6_227_020_800,
/* f(14): */                                        87_178_291_200,
/* f(15): */                                     1_307_674_368_000,
/* f(16): */                                    20_922_789_888_000,
/* f(17): */                                   355_687_428_096_000,
/* f(18): */                                 6_402_373_705_728_000,
/* f(19): */                               121_645_100_408_832_000,
/* f(20): */                             2_432_902_008_176_640_000,
	};
};

/*
	=========================  End of private tables  ========================
*/