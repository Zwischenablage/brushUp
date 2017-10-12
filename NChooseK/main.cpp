#include <iostream>
#include <string.h>

using namespace std;

int getFactorial(int n)
{
	if ( n == 1 ) return n;
	if ( n == 0 ) return 1;
	else return n * (getFactorial (n-1));
}

int getCombinations (int n, int k)
{	
	return getFactorial(n) / getFactorial(k) / getFactorial (n - k);
}

int getPermutation (int n, int k)
{
	return getFactorial(n) / getFactorial (n - k);
}

float getPow(float base, int exponent)
{
	if (exponent == 1) return base;
	return base * getPow(base, exponent - 1);
}

int main(int argc, char* argv[])
{
	int n = 8;
	int k = 3;
	cout << "" << n << " choose " << k << " = " << getCombinations(n, k) << " combinations "<< endl;
	cout << "" << n << " choose " << k << " = " << getPermutation(n, k) << " permutations "<< endl;
	
	
	int x = 2;
	int y = 8;
	cout << "" << x << " by the pow of " << y << " = " << getPow(x, y) << endl << endl;
	
	int totalOutcomes = getPow(x, y);
	
	
	// chance to hit exactly 3 heads out of 8 coin flips (fair coin)
	float probability = (float)getCombinations (n, k) / (float)totalOutcomes;
	cout << "probability (with outcomes) = " << probability * 100 << " percent" << endl << endl;;
	
	probability = (float)getCombinations (n, k) * getPow(0.5f,8);
	cout << "probability (with 0.5 probability) = " << probability * 100 << " percent" << endl << endl;

	n = 5;
	k = 3;
	cout << "" << n << " choose " << k << " = " << getCombinations(n, k) << " combinations "<< endl;
	// chance to hit exactly 3 out of 5 3-pointers with a 3-point-rate of 80%
	// hit = 0.8, miss = 0.2 --> hit,hit,hit,miss,miss = 0.8*0.8*0.8*0.2*0.2
	probability = (float)getCombinations (n, k) * getPow(0.8f,3) * getPow(0.2f,2);
	cout << "probability = " << probability * 100 << " percent" << endl << endl;
	
	
	// chance to hit at least 3 out of 5 3-pointers with a 3-point rate of 80%
	// this is the sum of: exact chance to hit 3/5 + exact chance to hit 4/5 + exact chance to hit 5/5

	probability = (float)getCombinations (n, 3) * getPow(0.8f,3) * getPow(0.2f,2)
				+ (float)getCombinations (n, 4) * getPow(0.8f,4) * getPow(0.2f,1)
				+ (float)getCombinations (n, 5) * getPow(0.8f,5);
	cout << "probability (to hit at least 3/5)= " << probability * 100 << " percent" << endl << endl;
}
