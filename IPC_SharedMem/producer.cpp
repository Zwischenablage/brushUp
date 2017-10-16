#include "common.h"
#include <signal.h>
#include <sstream>
#include <iostream>


volatile sig_atomic_t stop;

void inthand(int signum) {
    stop = 1;
}

int main (int argc, char *argv[])
{
    if (argc != 2) 
    {
        std::cout << "argc : " << argc << " Wrong number of arguments" << std::endl;
        return -1;
    }
    //Obtain handle value
    std::string s = argv[1]; 

    std::cout << "Sending string " << s << std::endl;

    //Open shared memory
    //Remove shared memory on construction and destruction
    struct shm_remove
    {
        shm_remove() { shared_memory_object::remove("MySharedMemory"); }
        ~shm_remove(){ shared_memory_object::remove("MySharedMemory"); }
    } remover;

    managed_shared_memory shm(create_only, "MySharedMemory", 10000);

    //Create allocators
    CharAllocator     charallocator  (shm.get_segment_manager());
    StringAllocator   stringallocator(shm.get_segment_manager());

    //This string is in only in this process (the pointer pointing to the
    //buffer that will hold the text is not in shared memory).
    //But the buffer that will hold "this is my text" is allocated from
    //shared memory
    MyShmString mystring(charallocator);
    mystring = "this is my text";
    //mystring = s.c_str();//"this is my text";

    //This vector is only in this process (the pointer pointing to the
    //buffer that will hold the MyShmString-s is not in shared memory).
    //But the buffer that will hold 10 MyShmString-s is allocated from
    //shared memory using StringAllocator. Since strings use a shared
    //memory allocator (CharAllocator) the 10 buffers that hold
    //"this is my text" text are also in shared memory.
    MyShmStringVector myvector(stringallocator);
    myvector.insert(myvector.begin(), 10, mystring);

    //This vector is fully constructed in shared memory. All pointers
    //buffers are constructed in the same shared memory segment
    //This vector can be safely accessed from other processes.
    MyShmStringVector *myshmvector = shm.construct<MyShmStringVector>("myshmvector")(stringallocator);
    myshmvector->insert(myshmvector->begin(), 10, mystring);

    //Destroy vector. This will free all strings that the vector contains
    shm.destroy_ptr(myshmvector);

    return 0;
}
