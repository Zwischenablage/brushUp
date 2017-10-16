INCLUDES=-I/usr/local/Cellar/boost/1.65.1/include

run: producer consumer
	echo "built targets producer & consumer"
	
producer: producer.o
	g++ -o producer producer.cpp $(INCLUDES)
		
consumer: consumer.o
	g++ -o consumer consumer.cpp $(INCLUDES)

	
clean:
	echo "cleaing up...."
	rm -rf *.o producer consumer