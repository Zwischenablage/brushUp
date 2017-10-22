#include <iostream>
#include <ctime>
#include <random>
#include <thread>         // std::this_thread::sleep_for
#include <chrono>         // std::chrono::seconds

using namespace std;

void printVector(vector<int> thisVec)
{
    for (vector<int>::iterator it = thisVec.begin(); it != thisVec.end() ;++it)
    {
        cout << *it << endl;
    }
}

void swap(vector<int>* list, int a, int b)
{
    int tmp = (*list)[a];
    (*list)[a] = (*list)[b];
    (*list)[b] = tmp;

    //cout << "swapping " << a << " with " << b << endl;
    /**cout << "SWAP: " << endl;
    printVector(*list);
    cout << endl;*/
}

int partition(vector<int>* list, int left, int right)
{
    int pivot = left;
    int x = (*list)[pivot];

    int j;

    for ( j = pivot + 1; j < right; ++j)
    {

        if ( (*list)[j] <= x)
        {
//            cout << "increasing pivot at " << j << endl;
            pivot++;
            swap ( list, pivot, j);
        }
    }

    swap (list, pivot, left);
    //cout << "### Returning pivot: " << pivot << endl;
    //printVector(*list);
    return pivot;
}

void doQuicksort(vector<int>* list, int left, int right)
{
    cout << "Doing quicksort on left=" << left << ", right=" << right << endl;

    if (left < right)
    {
        int pivot = partition (list, left, right);

        //seperately sort elements left & right of pivot
        doQuicksort(list, left, pivot);
        doQuicksort(list, pivot + 1, right);
    }

}


vector<int> quicksort(vector<int> unsorted)
{
    vector<int> sorted;
    doQuicksort(&unsorted, 0,unsorted.size());

    sorted = unsorted;
    return sorted;
}

int main(int argc, char* argv[])
{

    vector<int> unsorted;

    //get Random Number
    random_device rd;
    uniform_int_distribution<int> dist(0,20);
    for (int i = 0; i < 5; ++i)
    {
        int newRandom = dist(rd);
        unsorted.push_back(newRandom);
    }


    cout << "Printing unsorted list" << endl;
    for (vector<int>::iterator it = unsorted.begin(); it != unsorted.end() ;++it)
    {
        cout << *it << endl;
    }


    vector<int> sorted = quicksort(unsorted);
    cout << "Printing sorted list" << endl;
    for (vector<int>::iterator it = sorted.begin(); it != sorted.end() ;++it)
    {
        cout << *it << endl;
    }
}
