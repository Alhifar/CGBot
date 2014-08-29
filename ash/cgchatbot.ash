record mes
{
	string sender;
	string message;
	string channel;
	string timestamp;
};

void main( string sender, string msg, string channel )
{
	mes[int] queue;
	file_to_map( "chatbotqueue.txt",queue );
	int i = count(queue);
	queue[i].sender = sender;
	queue[i].message = msg;
	queue[i].channel = channel;
	queue[i].timestamp = format_date_time("hh:mm:ss z", time_to_string(), "hh:mm:ss");
	map_to_file( queue , "chatbotqueue.txt" );
}