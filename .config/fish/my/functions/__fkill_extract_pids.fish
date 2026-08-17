function __fkill_extract_pids -d "Extract PIDs (2nd column) from selected `ps aux` lines on stdin"
    awk '{print $2}'
end
