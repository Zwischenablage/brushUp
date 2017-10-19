INCLUDES=-I/usr/local/Cellar/boost/1.65.1/include
LIB=-L/usr/local/Cellar/boost//1.65.1/lib/ -lboost_thread-mt -lboost_system

run: producer 
	echo "built targets producer"
	
producer: producer.o
	g++ -o producer producer.cpp $(INCLUDES) $(LIB)
		
consumer: consumer.o
	g++ -o consumer consumer.cpp $(INCLUDES)

	
clean:
	echo "cleaing up...."
	rm -rf *.o producer 
