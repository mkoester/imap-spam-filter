local pw_handle = io.popen(os.getenv('IMAP_PASS_CMD'))
local pw = pw_handle:read('*l')
pw_handle:close()

local account = IMAP {
    server   = os.getenv('IMAP_HOST'),
    port     = tonumber(os.getenv('IMAP_PORT')),
    username = os.getenv('IMAP_USER'),
    password = pw,
    ssl      = 'tls1.2',
}

local data_dir   = os.getenv('DATA_DIR')
local inbox_name = os.getenv('INBOX_FOLDER')
local junk_name  = os.getenv('JUNK_FOLDER')
local queuefile  = data_dir .. '/state/mailfilter/spam-queue'
local inbox      = account[inbox_name]

local f = io.open(queuefile, 'r')
if not f then
    print('move-spam: queue file not found, nothing to do')
    return
end

local moved = 0
local missed = 0

for msgid in f:lines() do
    msgid = msgid:match('^%s*(.-)%s*$')  -- trim whitespace
    if msgid ~= '' then
        local msgs = inbox:contain_field('Message-ID', msgid)
        if #msgs > 0 then
            msgs:move_messages(account[junk_name])
            print('move-spam: moved to ' .. junk_name .. ': ' .. msgid)
            moved = moved + 1
        else
            print('move-spam: not found in ' .. inbox_name .. ': ' .. msgid)
            missed = missed + 1
        end
    end
end

f:close()

print(string.format('move-spam: done — moved %d, not found %d', moved, missed))

-- Clear the queue after processing
local qf = io.open(queuefile, 'w')
if qf then qf:close() end
