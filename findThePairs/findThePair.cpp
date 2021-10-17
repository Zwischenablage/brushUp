#include <iostream>
#include <stdio.h>

using namespace std;

int data[] = {1,2,4,4};
int target = 8;

void findIt(int sortedList[], int numElements)
{
	int * low = &data[0];
	int * high = &data[numElements];

	for (int i = 0 ; i < numElements; ++i)
	{
		//	cout << "[" << i << "] = " << sortedList[i] << endl;
		if ( (*low + *high) < target)
			++low;
		else if ( (*low + *high) > target)
			--high;
		else if ( (*low + *high) == target)
		{
			//cout << *low << " and " << *high << " are already summing up to " << target << endl;
			break;
		}
	}

	cout << "found pair (" << *low << "," << *high << ") summing up to " << target << endl;
}

int main (int argc, char* argv[])
{
 findIt(data, sizeof(data)/sizeof(data[0]));
 return 0;
}
