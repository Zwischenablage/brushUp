#include "common.h"
#include <iostream>
#include <chrono>
#include <thread>

boost::mutex mutex;
boost::condition_variable_any cond;
std::vector<int> random_numbers;

void wait(int seconds)
{
    boost::this_thread::sleep_for(boost::chrono::seconds(seconds));
}

void println(std::string string)
{
    std::cout << string << std::endl;
}

void fill()
{
    std::srand(static_cast<unsigned int>(std::time(0)));
    for (int i = 0; i < 3; ++i)
    {
        boost::unique_lock<boost::mutex> lock(mutex);
        random_numbers.push_back(std::rand());
        cond.notify_all();
        cond.wait(mutex);
    }

    println("end of fill()");
}

void fill2()
{
    std::srand(static_cast<unsigned int>(std::time(0)));
        boost::lock_guard<boost::mutex> lock(mutex);
    for (int i = 0; i < 3; ++i)
    {
        random_numbers.push_back(std::rand());
        cond.notify_all();
    }

    println("end of fill()");
}

void print()
{
    std::size_t next_size = 1;
    for (int i = 0; i < 3; ++i)
    {
        boost::unique_lock<boost::mutex> lock(mutex);
        if (random_numbers.size() != next_size)
        {
            std::cout << "cond.wait() at iteration " << i <<  std::endl;
            cond.wait(mutex);
        }
        std::cout << "[" << i << "] " << random_numbers.back() << '\n';
        ++next_size;
        cond.notify_all();
    }
    println("end of print()");
}

void print2()
{
    boost::lock_guard<boost::mutex> lock(mutex);
    if (random_numbers.size() != 2)
    {
        std::cout << "cond.wait() at iteration 0" <<  std::endl;
        cond.wait(mutex);
    }

    for (int i = 0; i < 3; ++i)
    {
        std::cout << "[" << i << "] " << random_numbers[i] << std::endl;
    }

    println("end of print2()");
}

int main()
{

    /* print() and fill() are the examples taken from https://dieboostcppbibliotheken.de/boost.thread-synchronisation.
     * This adds 3 random numbers to the vector random_numbers() and synchronizes the fill() vs. print() per cond var.
     * In contrary to print2() / fill2() this synchronizes print/fill with every number added to the vector.
     * While fill2() / print 2() add all 3 numbers first to the vector and signals the cond var once all values have been added. */
    std::cout << std::endl;
    std::cout << "<START>" << std::endl;
    boost::thread t2(print);
    wait(3);
    boost::thread t1(fill);
    t1.join();
    t2.join();

    random_numbers.clear();
    std::cout << std::endl;
    std::cout << "<START>" << std::endl;
    boost::thread t3(print2);
    wait(3);
    boost::thread t4(fill2);
    t3.join();
    t4.join();
}
