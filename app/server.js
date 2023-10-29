'use strict';

var express = require('express');
var app = express();

app.set("port", process.env.PORT || 80);

app.get('/', function (req, res) {
   res.writeHead(200, {'Content-Type': 'application/json'});
   var response = { "response" : "Hi, Amazon Web Service" }
   console.log(response);
   res.end(JSON.stringify(response));
})

var server = app.listen(app.get("port"), function () {
  var host = server.address().address
  var port = server.address().port
  console.log("Node.js API app listening at http://%s:%s", host, port)
})
