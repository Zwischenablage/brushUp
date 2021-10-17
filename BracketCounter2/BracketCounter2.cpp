#include <iostream>
#include <stdio.h>

using namespace std;

int countBrackets(char* inputString);

int main(int argc, char* argv[] )
{
	cout << "arguments provided to " << argv[0] << ":" << endl;
	for (int i=1; i< argc ;++i)
	{
		cout << "[" << i << "]: " << argv[i] << endl << endl;
	}

	if (argc > 1)
	{
		//cout << "Found " << countBrackets(argv[1]) << " brackets" << endl;
		countBrackets(argv[1]);
	}
}

int countBrackets(char* inputString)
{
	int openBrackets = 0;
	int closedBrackets = 0;

	for (int j = 0; j < strlen(inputString) ; ++j)
	{
		//cout << "j=" << j << endl;
		//cout << "cb [" << j << "] : " << inputString[] << endl;
		if (inputString[j] == '(' )
			++openBrackets;
		else if (inputString[j] == ')' )
			++closedBrackets;
	}

	cout << "found " << openBrackets << " opening and " << closedBrackets << " closing brackets" << endl;
	return 0;
}
