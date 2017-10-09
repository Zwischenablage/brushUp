#include <iostream>
#include <string.h>

using namespace std;

int areEqual(int n1, int n2)
{
	return ((n1 - n2)*(n1-n2)) ? 1 : 0;
}

int main(int argc, char* argv[])
{
	int n1 = 3;
	int n2 = 3;

	cout << "Comparing " << to_string(n1) << " with " << to_string(n2) << ": Those numbers are " << (areEqual(n1, n2) ? "NOT " : "") << "equal! " << endl;
	
	n1 = 12, n2 = 44;
	cout << "Comparing " << to_string(n1) << " with " << to_string(n2) << ": Those numbers are " << (areEqual(n1, n2) ? "NOT " : "") << "equal! " << endl;
	
	n1 = 59, n2 = 59;
	cout << "Comparing " << to_string(n1) << " with " << to_string(n2) << ": Those numbers are " << (areEqual(n1, n2) ? "NOT " : "") << "equal! " << endl;
	
}
