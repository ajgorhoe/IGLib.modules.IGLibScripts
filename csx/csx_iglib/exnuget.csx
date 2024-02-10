

#r "nuget: Newtonsoft.Json, 13.0.1"
// Loading a library via Nuget (define package version for caching):

using System;
using System.IO;

using Newtonsoft.Json;

Console.WriteLine(Environment.NewLine + "Interpreting test-nuget.csx..." + Environment.NewLine);


public class PlaceInfo
{

	public PlaceInfo()
    {
		Id = _nextId++;
    }

	protected static int _nextId = 0;

	public int Id { get; private set; }

	public string Name { get; set; }

	public string Country { get; set; }

}

var city1 = new PlaceInfo
{
	Name = "Vienna",
	Country="Austria"
};

Console.WriteLine(nameof(city1) + ":");
var scity1 = JsonConvert.SerializeObject(city1);
Console.WriteLine(scity1);

Console.WriteLine(Environment.NewLine + "Script test-nuget.csx finished." + Environment.NewLine);
