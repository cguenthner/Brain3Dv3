% prepare the parameters
SIFTflowpara.alpha=2;
SIFTflowpara.d=40;
SIFTflowpara.gamma=0.005;
SIFTflowpara.nlevels=4;
SIFTflowpara.wsize=5;
SIFTflowpara.topwsize=20;
SIFTflowpara.nIterations=60;
patchsize=8;
gridspacing=1;

reg2{1} = reg{1};
for i = 2:100

    % Step 1. Load and downsample the images

    im1=reg2{i-1};
    im2=reg{i};

    im1=im2double(im1);
    im2=im2double(im2);

    % Step 2. Compute the dense SIFT image

    % patchsize is half of the window size for computing SIFT
    % gridspacing is the sampling precision

    Sift1=dense_sift(im1,patchsize,gridspacing);
    Sift2=dense_sift(im2,patchsize,gridspacing);


    % Step 3. SIFT flow matching

    [vx,vy,energylist]=SIFTflowc2f(Sift1,Sift2,SIFTflowpara);

    % Step 4.  Visualize the matching results
    Im1=im1(patchsize/2:end-patchsize/2+1,patchsize/2:end-patchsize/2+1,:);
    Im2=im2(patchsize/2:end-patchsize/2+1,patchsize/2:end-patchsize/2+1,:);
    reg2{i}=warpImage(Im2,vx,vy)*255;
    
end

