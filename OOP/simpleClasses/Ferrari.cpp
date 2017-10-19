#include "Common.h"
#include "Ferrari.h"

Ferrari::Ferrari(int maxSpeed, int horsePower, int maxPassengers, std::string type) : Car (maxSpeed, maxPassengers, "Ferrari", type) , m_horsePower(horsePower)
{
    println("Ferrari() Constructor called.");
    return;
}
Ferrari::~Ferrari()
{
    return;
}


int main()
{
    println ("this is main of ferrari");

    Ferrari testarossa(300, 440, 4, "Testarossa 512 TR");

    cout << endl;
    cout << "This is a " << testarossa.getDescription() << endl;
    cout << "It has " << testarossa.getNumSeats() << " seats, " << testarossa.getHP() << " horsepower which it brings up to " << testarossa.getMaxSpeed() << " km/h" << endl;
    return 1;
}
