var express = require('express'),
    async = require('async'),
    fs = require('fs'),
    path = require('path'),
    { Pool } = require('pg'),
    cookieParser = require('cookie-parser'),
    app = express(),
    server = require('http').Server(app),
    io = require('socket.io')(server);

var port = process.env.PORT || 8080;

// the two vote options, same variables the vote app uses
var optionA = process.env.OPTION_A || 'Cats';
var optionB = process.env.OPTION_B || 'Dogs';

// database settings come from the environment, never from the code
var dbConfig = {
  host: process.env.DB_HOST || 'db',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || 'postgres'
};

if (!dbConfig.password) {
  console.error('DB_PASSWORD is not set, the database login will fail');
}

io.on('connection', function (socket) {

  socket.emit('message', { text : 'Welcome!' });

  socket.on('subscribe', function (data) {
    socket.join(data.channel);
  });
});

var pool = new Pool(dbConfig);

async.retry(
  {times: 1000, interval: 1000},
  function(callback) {
    pool.connect(function(err, client, done) {
      if (err) {
        console.error("Waiting for db");
      }
      callback(err, client);
    });
  },
  function(err, client) {
    if (err) {
      return console.error("Giving up");
    }
    console.log("Connected to db");
    getVotes(client);
  }
);

function getVotes(client) {
  client.query('SELECT vote, COUNT(id) AS count FROM votes GROUP BY vote', [], function(err, result) {
    if (err) {
      console.error("Error performing query: " + err);
    } else {
      var votes = collectVotesFromResult(result);
      io.sockets.emit("scores", JSON.stringify(votes));
    }

    setTimeout(function() {getVotes(client) }, 1000);
  });
}

function collectVotesFromResult(result) {
  var votes = {a: 0, b: 0};

  result.rows.forEach(function (row) {
    votes[row.vote] = parseInt(row.count);
  });

  return votes;
}

// escape the option names before putting them into the HTML page
function escapeHtml(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// build the page once at startup with the real option names filled in
var indexHtml = fs.readFileSync(path.join(__dirname, 'views', 'index.html'), 'utf8')
  .replace(/__OPTION_A__/g, escapeHtml(optionA))
  .replace(/__OPTION_B__/g, escapeHtml(optionB));

function sendIndex(req, res) {
  res.type('html').send(indexHtml);
}

app.use(cookieParser());
app.use(express.urlencoded({ extended: false }));

// "/" must be handled before express.static, otherwise static serves the raw template
app.get(['/', '/index.html'], sendIndex);
app.use(express.static(path.join(__dirname, 'views'), { index: false }));

// simple endpoint for Kubernetes liveness/readiness probes
app.get('/healthz', function (req, res) {
  res.status(200).send('ok');
});

server.listen(port, function () {
  var port = server.address().port;
  console.log('App running on port ' + port);
});
