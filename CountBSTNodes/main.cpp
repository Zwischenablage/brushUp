#include <iostream>
#include <string.h>

using namespace std;

/* the structure of a BST Node is as follows: */
struct Node {
int data;
Node * right, * left;
};

struct Node * root;

bool isInRange(int value, int l, int h)
{
	if ( (value >= l) & (value <= h) )
		return true;

	return false;
}

void countNodesInRange(Node *thisNode, int l, int h, int* nodesFound)
{
	if (isInRange(thisNode->data, l, h))
	{
		(*nodesFound) += 1;
	}

	if ( thisNode->left != NULL)
		countNodesInRange(thisNode->left, l, h, nodesFound);
	
	if ( thisNode->right != NULL)
		countNodesInRange(thisNode->right, l, h, nodesFound);
}

int getCountOfNode(Node *startNode, int l, int h)
{
	int nodesWithinRange = 0;
	if (root == NULL)
		return 0;

	countNodesInRange(startNode, l, h, &nodesWithinRange);

	return nodesWithinRange;

}

void insertNode(int data)
{
	struct Node *tempNode = (struct Node*) malloc(sizeof(struct Node));
	struct Node *current;
	struct Node *parent;

	tempNode->data = data;
	tempNode->left = NULL;
	tempNode->right = NULL;


	if (root == NULL)
	{
		root = tempNode;
		cout << "Inserting root node = " << data << endl;
	}
	else
	{
		current = root;
		parent = NULL;

		while (1)
		{
			parent = current;

			//go to left of tree
			if (data < parent->data)
			{
				current = current->left;

				if (current == NULL)
				{
					parent->left = tempNode;
					cout << "Inserting new left Node = " << data << endl;
					return;
				}
			}
			else //go to right side
			{
				current = current->right;

				if (current == NULL)
				{
					parent->right = tempNode;
					cout << "Inserting new right Node = " << data << endl;
					return;
				}
			}
		}
	}
}

int main(int argc, char* argv[])
{
	root = NULL;

	int nodeValues[] = {10,5,50,40,100};
	int numNodes = sizeof(nodeValues) / sizeof(*nodeValues);
	int lowerLimit = 5;
	int upperLimit = 45;

	for (int i = 0; i < numNodes; ++i)
	{
		insertNode(nodeValues[i]);
	}

	int nodesFound = getCountOfNode(root, lowerLimit, upperLimit);
	cout << "Found " << nodesFound << " nodes, within limits of " << lowerLimit << " and " << upperLimit << "." << endl;



}
