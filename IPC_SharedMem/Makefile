INCLUDES=-I/usr/local/Cellar/boost/1.65.1/include
#LIB=-L/usr/local/Cellar/boost//1.65.1/lib/ -lboost_thread-mt

run: producer consumer
	echo "built targets producer & consumer"
	
producer: producer.o
	g++ -o producer producer.cpp $(INCLUDES)
		
consumer: consumer.o
	g++ -o consumer consumer.cpp $(INCLUDES)

	
clean:
	echo "cleaing up...."
	rm -rf *.o producer consumer