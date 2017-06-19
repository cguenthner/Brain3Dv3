function [] = Brain3D( )

    OpenWindows = [];

    ScreenSize = get(0,'ScreenSize');
    ScreenCenter = ScreenSize/2;
    ScreenCenter = ScreenCenter(3:4);
    
    hOpenFig = figure('Position',[ScreenCenter(1)-130 ScreenCenter(2)-110 260 220],...
        'Name','3D Brain',...
        'NumberTitle','off',...
        'Toolbar','none',...
        'Resize','off',...
        'Menubar','none',...
        'Color',[0.9412 0.9412 0.9412]);
    
    hOpenExisting = uicontrol('Style','pushbutton','String','Open Existing Project',...
        'Position',[10 150 240 60],...
        'Callback',{@OpenExisting});
    hNew = uicontrol('Style','pushbutton','String','Start New Project',...
        'Position',[10 80 240 60],...
        'Callback',{@StartNew});
    hExit = uicontrol('Style','pushbutton','String','Exit',...
        'Position',[10 10 240 60],...
        'Callback',{@ExitProg});


%%
    function OpenExisting(source, eventdata)
        [fn,FilePath,~] = uigetfile({'*.mat' '3D Brain Project File'});
        
        if ischar(fn) && ischar(FilePath)
            fn = strcat(FilePath,fn);
            OpenWindows(end+1) = BrainMeat(fn);
        end
    end

%%
    function StartNew(source, eventdata)
        OpenWindows(end+1) = BrainMeat(1);
    end

%%
    function ExitProg(source, eventdata)
        close(hOpenFig);
        for i = 1:length(OpenWindows);
            if ishandle(OpenWindows(i))
                close(OpenWindows(i));
            end
        end
    end

end

