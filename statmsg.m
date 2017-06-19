function h = statmsg(str)
    h = msgbox(str,'','modal');
    set(h,'CloseRequestFcn','');
    child = get(h,'Children');
    delete(child(end));
end