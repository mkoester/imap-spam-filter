local pw_handle = io.popen('cat /mnt/data/spamfilter/config/mbsync/mailpass')
local pw = pw_handle:read('*l')
pw_handle:close()

local account = IMAP {
    server   = 'imap.mailserver.com',
    port     = 993,
    username = 'user@domain.tld',
    password = pw,
    ssl      = 'tls1.2',
}

local queuefile = '/mnt/data/spamfilter/state/mailfilter/spam-queue'
local inbox = account['INBOX']

local f = io.open(queuefile, 'r')
if not f then return end

for msgid in f:lines() do
    msgid = msgid:match('^%s*(.-)%s*$')  -- trim whitespace
    if msgid ~= '' then
        local msgs = inbox:contain_field('Message-ID', msgid)
        if #msgs > 0 then
            msgs:move_messages(account['Junk'])
        end
    end
end

f:close()

-- Clear the queue after processing
local qf = io.open(queuefile, 'w')
if qf then qf:close() end
