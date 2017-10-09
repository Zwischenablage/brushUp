#include <iostream>
#include <string.h>

using namespace std;

int countBracketLoops(char* inputString)
{
	int openBracketsFound = 0;
	int closedBracketsFound = 0;

	while (*inputString != NULL)
	{
		//cout << "current char is " << *inputString << endl;
		if ( *inputString == '(')
		{
			++openBracketsFound;
		}
		else if (*inputString == ')')
		{
			++closedBracketsFound;
		}
		++inputString;
	}

	return (openBracketsFound<=closedBracketsFound) ? openBracketsFound : closedBracketsFound;
}

int main(int argc, char* argv[])
{

	if ( argc > 1 ) 
	{
		cout << "Found " << countBracketLoops(argv[1]) << " bracket loops in " << argv[1] << endl;
	}
}
