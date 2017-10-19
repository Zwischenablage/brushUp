#include "Common.h"
#include "Car.h"

#define WHEELS 4
Car::Car(int maxSpeed, int maxPassengers, std::string make, std::string type) : Vehicle (maxSpeed, WHEELS, maxPassengers, make, type)
{
    println("Car() Constructor called.");
    return;
}
Car::~Car()
{
    return;
}


int Car::getMaxSpeed()
{
    return m_maxSpeed;
}
int Car::getNumWheels()
{
    return m_numWheels;
}
int Car::getMaxPessengers()
{
    return m_maxPassengers;
}

std::string Car::getMake()
{
    return m_make;
}
std::string Car::getType()
{
    return m_type;
}
