// Stand-in for `ruflo mcp start`: replies to echo, aborts on crash, stalls on
// hang. Appends one line per received method to $FAKE_STATE so a test can see
// how often the supervisor restarted it and replayed the handshake.
import { appendFileSync } from 'node:fs';

const record = (method) => {
  if (process.env.FAKE_STATE) appendFileSync(process.env.FAKE_STATE, `${process.pid} ${method}\n`);
};
const reply = (msg) => process.stdout.write(JSON.stringify(msg) + '\n');

let buffer = '';
process.stdin.on('data', (chunk) => {
  const lines = (buffer + chunk).split('\n');
  buffer = lines.pop() ?? '';
  for (const line of lines) {
    if (!line.trim()) continue;
    const msg = JSON.parse(line);
    record(msg.method);
    if (msg.method === 'initialize') {
      reply({ jsonrpc: '2.0', id: msg.id, result: { serverInfo: { name: 'fake', version: '1' } } });
    } else if (msg.method === 'tools/call') {
      const tool = msg.params?.name;
      if (tool === 'crash') process.abort();
      if (tool === 'hang') continue;
      reply({ jsonrpc: '2.0', id: msg.id, result: { content: [{ type: 'text', text: `${tool}:${process.pid}` }] } });
    }
  }
});
