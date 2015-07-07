function [dipoles, L, moments, weights, rv, state] = bfpf(data,K,vertices,nDipoles,nParticles,Q_location,Q_data,state,flag_all)
% check inputs
nChan = size(data,1);
nTimes = size(data,2);
if ~any(size(vertices)==3)
    error('Vertices must be a 3 x nVert matrix')
elseif size(vertices,2)==3
    vertices = vertices';
end
nVert = size(vertices,2);
nK = size(K,2);
if ~exist('Q_location','var') || isempty(Q_location)
    Q_location = 1*eye(3); end
if ~exist('Q_data','var') || isempty(Q_data)
    Q_data = 3*nChan*eye(nChan); end
rng(0);
if exist('state','var') && ~isempty(state)
    flag_state = true;
else
    flag_state = false;
end
if ~exist('flag_all','var')
    flag_all = false;
end
if nVert==length(K)
    flag_fixedDir = true;
else
    flag_fixedDir = false;
end
K = double(K); % add check function


if flag_state
    Ktpi = state.Ktpi;
    Kpi_individual = state.Kpi_individual;
    cQ_location = state.cQ_location;
    weights = state.weights;
    L = state.L;
else
    % precalculate pseudo inverse of Lead Field Matrix transposed
    Ktpi = pinv(K');
    Kpi_individual = zeros(size(K'));
%     for it = 1:nK
%         Kpi_individual(it,:) = pinv(K(:,it)); end
    for it = 1:length(Kpi_individual)/3
        Kpi_individual(tri_index(it,nVert,flag_fixedDir),:) = pinv(K(:,tri_index(it,nVert,flag_fixedDir))); end
    cQ_location = chol(Q_location);
    state.Ktpi = Ktpi;
    state.Kpi_individual = Kpi_individual;
    state.cQ_location = cQ_location;
    state.nParticles = nParticles;
    % initialize weights
    weights = ones(1,nParticles)/nParticles;
    % initialize dipole locations
    L = randi(nVert,1,nParticles);
end

if flag_all
    for it = 1:nTimes
        nParticles = nVert;
%         weights = ones(1,nParticles)/nParticles;
        % initialize dipole locations
        L = 1:nVert;
        moments = zeros(nK,1);
        for itM = 1:nParticles
            % make linearly constrained minimum variance(LCMV) beamforming filter
%             W0 = Ktpi(:,tri_index(unique(Lold(itM)),nVert))*K(:,tri_index(unique(Lold(itM)),nVert))';
%             W0 = eye(nChan);
            % calculate moments vector
            moments(tri_index(itM,nParticles,flag_fixedDir)) = Kpi_individual(tri_index(L(itM),nVert,flag_fixedDir),:)*data(:,it);
%             moments(tri_index(itM,nParticles,flag_fixedDir)) = Kpi_individual(tri_index(L(itM),nVert,flag_fixedDir),:)*(W0'*data(:,it));
        end
        %     moments = sparse([ones(nParticles,1);2*ones(nParticles,1);3*ones(nParticles,1)],repmat(Lold',3,1),moments',3,nVert);
        % update new weights
        if flag_fixedDir
%             moments = max(moments,0);
            y_hat = bsxfun(@times,moments',K(:,tri_index(L,nVert,flag_fixedDir)));
        else
            y_hat = sum(reshape(bsxfun(@times,moments',K(:,tri_index(L,nVert,flag_fixedDir))),[nChan,nParticles,3]),3);
        end
        p_ylx = mvnpdf(bsxfun(@minus,data(:,it),y_hat)',zeros(nChan,1)',Q_data)';
        weights = p_ylx;
        % normalize weights
        weights = weights/sum(weights);
    end
else
    % iterate
    for it = 1:nTimes
        % resample from L (with replacement) according to importance weights
        L = datasample(L,nParticles,'weights',weights);
        Lold = L;
        % generate random numbers
        w = cQ_location*randn(3,nParticles);
        % displace current locations
        vtemp = vertices(:,L) + w;
        % lock new location to existing vertex
        for itPart = 1:nParticles
            [~,L(itPart)] = min(row_pnorm(bsxfun(@minus,vertices,vtemp(:,itPart)),2,'column'));
        end
        if flag_fixedDir
            moments = zeros(nParticles,1);
        else
            moments = zeros(3*nParticles,1);
        end
        for itM = 1:nParticles
            % make linearly constrained minimum variance(LCMV) beamforming filter
    %         W0 = Ktpi(:,tri_index(unique(Lold(itM)),nVert))*K(:,tri_index(unique(Lold(itM)),nVert))';
%             W0 = eye(nChan);
            % calculate moments vector
%             moments(tri_index(itM,nParticles,flag_fixedDir)) = Kpi_individual(tri_index(Lold(itM),nVert,flag_fixedDir),:)*W0'*data(:,it);
            moments(tri_index(itM,nParticles,flag_fixedDir)) = Kpi_individual(tri_index(Lold(itM),nVert,flag_fixedDir),:)*data(:,it);
        end
    %     moments = sparse([ones(nParticles,1);2*ones(nParticles,1);3*ones(nParticles,1)],repmat(Lold',3,1),moments',3,nVert);
        % update new weights
        if flag_fixedDir
            y_hat = bsxfun(@times,moments',K(:,tri_index(L,nVert,flag_fixedDir)));
        else
            y_hat = sum(reshape(bsxfun(@times,moments',K(:,tri_index(L,nVert,flag_fixedDir))),[nChan,nParticles,3]),3);
        end
        p_ylx = mvnpdf(bsxfun(@minus,data(:,it),y_hat)',zeros(nChan,1)',Q_data)';
        weights = p_ylx;
%         weights = weights.*p_ylx;
        % normalize weights
        weights = weights/sum(weights);
        weights(weights<=.01/nParticles) = min(weights(weights>.01/nParticles));
    end
end

dipoles = struct('location',[],'moment',[]);
[~,ind] = sort(weights,2,'descend');
for it = 1:nDipoles
    dipoles(it).location = vertices(:,L(ind(it)));
    dipoles(it).L = tri_index(ind(it),nParticles,flag_fixedDir);
    dipoles(it).moment = moments(dipoles(it).L);
end

state.weights = weights;
state.L = L;

% does not support multiple dipoles or multiple data points atm
rv = var(data - y_hat(:,dipoles.L(1)))/var(data);


function index = tri_index(index,nVert,flag_fixedDir)
if flag_fixedDir
    return
else
    if iscolumn(index)
        index = index'; end
    index = [index,index+nVert,index+2*nVert];
end