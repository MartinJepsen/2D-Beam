classdef FiniteElementModel < handle
    properties
        mesh {isstruct}
        n_dof
        Kg
        Cg
        Mg
        B                   % strain mapping matrix
        H
        s
        modal_parameters
        results
    end

    methods
        function self = FiniteElementModel()

        end

        function from_xlsx(self, meshpath)
                        % FiniteElementModel(meshpath)
            %   * meshpath (str/char): path to .xlsx file containing mesh and element data
            %   * .xlsx file must have two sheets; 'coords' and 'elements'
            %   * 'coords' contains n_node rows with the columns containing x and y coordinates of each node
            %   * 'elements' contains:
            %       * Column 1: start node of each element
            %       * Column 2: end node of each element
            %       * Column 3: cross-sectional area of each element
            %       * Column 4: modulus of elasticity of each element
            %       * Column 5: area moment of interia of each element
            %       * Column 6: mass density of each element

            % constructor
            self.mesh.meshpath = meshpath;
            self.mesh.coordinates = readmatrix(meshpath,'Sheet','coords');
            elements = readmatrix(meshpath,'Sheet','elements');
            self.mesh.topology = elements(:,[1,2]);
            self.mesh.element_properties.A = elements(:,3);
            self.mesh.element_properties.E = elements(:,4);
            self.mesh.element_properties.I = elements(:,5);
            self.mesh.element_properties.rho = elements(:,6);
            self.mesh.n_node = size(self.mesh.coordinates,1);
            self.mesh.n_el = size(self.mesh.topology,1);
        end

        function assembly(self, type, bc_dof)
            % Class method FiniteElementModel.assembly(type, bc_dof)
            % type (str): "bar" or "beam"
            % bc_dof (array): indices of rows and columns in system matrices to remove

            % check for valid element type
            if ~any(strcmp({'bar', 'beam'}, type))
                throw('Unrecognised element type')
            end

            % mirror some values from self
            n_node = self.mesh.n_node;
            n_el = self.mesh.n_el;
            topology = self.mesh.topology;
            coords = self.mesh.coordinates;

            % element lengths
            self.mesh.element_properties.L = zeros(n_el,1);
            self.mesh.element_properties.rot = zeros(n_el, 2);

            % loop over elements
            for el = 1:n_el
                % element length and orientation
                dx = coords(topology(el, 2), 1) - coords(topology(el, 1), 1);
                dy = coords(topology(el, 2), 2) - coords(topology(el, 1),2);
                L = norm([dx dy]');
                self.mesh.element_properties.L(el) = L;
                c = dx/L;
                s = dy/L;
                self.mesh.element_properties.rot(el,:) = [c, s];

                if type == "bar"
                    if el == 1
                        self.mesh.element_type = type;
                        for node = 1:n_node
                            dof_node(node, :)=[node * 2 - 1, node * 2];
                        end
                        n_dof = dof_node(end);
                        Kg = zeros(n_dof);
                        Mg = zeros(n_dof);
                    end
                    % Determines which DOF belong to which elements, for indexing purposes
                    dof_element(el, :) = [dof_node(topology(el,1),:), dof_node(topology(el,2),:)];

                    % Transformation matrix
                    T=[c s 0 0;
                      -s c 0 0;
                       0 0 c s;
                       0 0 -s c];

                    A = self.mesh.element_properties.A(el);
                    E = self.mesh.element_properties.E(el);
                    rho = self.mesh.element_properties.rho(el);

                    % Element stiffness matrix in local coordinates
                    kel = A * E / L * [1, 0, -1, 0; 0, 0, 0, 0; -1, 0, 1, 0; 0, 0, 0, 0];
                    mel = rho * A * L / 6 * [2, 0, 1, 0; 0, 0, 0, 0; 1, 0, 2, 0; 0, 0, 0, 0];

                elseif type == "beam"
                    if el == 1
                        self.mesh.element_type = type;
                        for node = 1:n_node
                            dof_node(node, :)=[node * 3 - 1, node * 2];
                        end
                        n_dof = dof_node(end);
                        Kg = zeros(n_dof);
                        Mg = zeros(n_dof);
                    end
                    % Determines which DOF belong to which elements, for indexing purposes
                    dof_element(el, :) = [dof_node(topology(el,1),:), dof_node(topology(el,2),:)];

                    % Transformation matrix
                    T=[c s 0 0  0 0;
                      -s c 0 0  0 0;
                       0 0 1 0  0 0
                       0 0 0 c  s 0;
                       0 0 0 -s c 0
                       0 0 0 0  0 1];

                    A = self.mesh.element_properties.A(el);
                    E = self.mesh.element_properties.E(el);
                    rho = self.mesh.element_properties.rho(el);
                    I = self.mesh.element_properties.I(el);

                    % Element stiffness matrix in local coordinates
                    k_1 = E * A / L;
                    k_2 = (12 * E * I) / L^3;
                    k_3 = (6 * E * I) / L^2;
                    k_4 = (2 * E * I) / L;

                    kel = [k_1  , 0   , 0      , -k_1, 0   , 0       ;
                           0    , k_2 , k_3    , 0   , -k_2, k_3     ;
                           0    , k_3 , 2 * k_4, 0   , -k_3, k_4     ;
                           -k_1 , 0   , 0      , k_1 , 0   , 0       ;
                           0    , -k_2, -k_3   , 0   , k_2 , k_3     ;
                           0    , k_3 , k_4    , 0   , -k_3, 2 * k_4];

                    mel = rho * A * L / 420 * [
                      140, 0      , 0        , 70 , 0      , 0       ;
                      0  , 156    , 22 * L   , 0  , 54     , -13 * L ;
                      0  , 22 * L , 4 * L^2  , 0  , 13 * L , -3 * L^2;
                      70 , 0      , 0        , 140, 0      , 0       ;
                      0  , 54     , 13 * L   , 0  , 156    , -22 * L ;
                      0  , -13 * L, -3 * L ^2, 0  , -22 * L, 4 * L^2];
                end

                % stiffness matrix
                ke = T' * kel * T;
                Kg(dof_element(el, :), dof_element(el, :)) =...
                    Kg(dof_element(el, :), dof_element(el, :)) + ke;

                % mass matrix
                me = T' * mel * T;
                Mg(dof_element(el, :), dof_element(el, :)) =...
                    Mg(dof_element(el, :), dof_element(el, :)) + me;
            end

            % apply BCs
            Kg(bc_dof, :) = [];
            Kg(:, bc_dof) = [];
            Mg(bc_dof, :) = [];
            Mg(:, bc_dof) = [];

            self.n_dof = n_dof;
            self.mesh.bc_dof = bc_dof;

            self.Kg = Kg;
            self.Mg = Mg;

            self.mesh.element_properties.dof_element = dof_element;
        end
 %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        function modal_damping(self, zeta)
            % modal_damping(zeta)
            % applies damping ratio zeta to all modes

            [Phi, Lambda] = eig(self.Kg, self.Mg);
            omega = sqrt(diag(Lambda));
            m_n = sqrt(diag(Phi' * self.Mg * Phi)); % mass-normalised eigenvectors
            Phi = Phi * diag(1./m_n);
            C_tilde = diag(2 * zeta * omega);
            self.Cg = inv(Phi)' * C_tilde * inv(Phi);
            zetas = diag(C_tilde) ./ (2 * omega);
            self.modal_parameters.zeta = zetas;
            self.modal_parameters.Phi = Phi;
            self.modal_parameters.Lambda = Lambda;
            self.modal_parameters.omega = omega;
        end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        function f = modeshape(self, modenum, scale)
            % modeshape(modenum, scale)
            % plots modeshape
            n_dof = self.n_dof;
            coords = self.mesh.coordinates;
            topology = self.mesh.topology;
            L = self.mesh.element_properties.L;

            Phi = self.modal_parameters.Phi(:, modenum);
            Phi_mode = zeros(n_dof, 1);  % empty mode shape
            free_dof = setdiff(1:n_dof, self.mesh.bc_dof);
            Phi_mode(free_dof) = Phi;
            Phi_mode = Phi_mode/max(abs(Phi_mode));

            if Phi_mode(find(abs(Phi_mode) == max(abs(Phi_mode)))) < 0
                Phi_mode = - Phi_mode;
            end

            disp(['MESSAGE: Plotting mode shape number ',num2str(modenum),'.'])

            f = figure;
            hold on
            grid on

            for i = 1:size(topology,1)
                % makes x-y-z coordinates for the end and start node of the ith element as
                % [x1, y1, x2, y2]
                lines(i,:) = [coords(topology(i,1),:) coords(topology(i,2),:)];

                % DOF numbers of the start node of the i'th element
                ind1 = [(topology(i,1)*2-1):(topology(i,1)*2)];
                % DOF numbers of the end node of the i'th element
                ind2 = [(topology(i,2)*2-1):(topology(i,2)*2)];
                % Line start and end points in format [x1 y1 z1 x2 y2 z2]
                shape_coords(i, :)=[Phi_mode(ind1)', Phi_mode(ind2)'];
            end

            modeshape = lines + shape_coords * scale;

            for i = 1:size(topology,1)
                % Plots the lines and nodes
                plot(lines(i,[1,3]),lines(i,[2,4]),'.-k','MarkerSize',10,'linewidth',1.2)
                plot(modeshape(i,[1,3]),modeshape(i,[2,4]),'.-r','MarkerSize',10,'linewidth',1.2)
            end

            axis equal
            xlabel('x')
            ylabel('y')
        end

        function [eps, B] = strains_from_disp(self, d)
            % if d is empty/undefined, only the strain mapping matrix is computed
            n_dof = self.n_dof;
            n_el = self.mesh.n_el;
            lengths = self.mesh.element_properties.L;
            rot = self.mesh.element_properties.rot;
            dof_element = self.mesh.element_properties.dof_element;

            if exist('d', 'var') && ~isempty(d)
                % add zero displacements at constrained DOF
                if numel(d) ~= self.n_dof
                    bc = self.mesh.bc_dof;
                    d_ = zeros(n_dof,1);
                    d_(setdiff(1:n_dof, bc)) = d;
                end
            end

            B = zeros(n_el, n_dof);
            for el = 1:n_el
                c = rot(el, 1);
                s = rot(el, 2);

                idx = dof_element(el, :);
                B(el, idx) = [-c, -s, c, s] / lengths(el);
            end

            if exist('d', 'var') && ~isempty(d)
                eps = B * d_;
                self.results.eps = eps;
                self.results.d = d_;
            end
            self.B = B;

        end

        function transfer_matrix(self, s)
            % Get s-value from self if not supplied
            if ~exist('s', 'var') && ~isempty(self.s)
                s = self.s;
            elseif ~exist('s', 'var') && isempty(self.s)
                disp('WARNING (transfer_matrix): No s-value could be found. s = 0.')
                s = 0;
            end

            try
                self.H = inv(self.Mg*s^2 + self.Cg * s + self.Kg);
                self.s = s;
            catch
                disp('ERROR (transfer_matrix): Missing s value parameter.')
            end
        end

        function plotdisp(self, d)

            n_dof = self.n_dof;
            if exist('d', 'var') && ~isempty(d)
                % add zero displacements at constrained DOF
                if numel(d) ~= self.n_dof
                    bc = self.mesh.bc_dof;
                    d_ = zeros(n_dof,1);
                    d_(setdiff(1:n_dof, bc)) = d;
                end
            else
                try
                    d_ = self.results.d;
                catch
                    error('No displacement vector found')
                end
            end

            topology = self.mesh.topology;
            coords = self.mesh.coordinates;

            for i = 1:size(topology,1)
                % makes x-y coordinates for the end and start node of the ith element as
                lines(i,:) = [coords(topology(i,1),:) coords(topology(i,2),:)];
            end

            def_shape = lines;

            for i=1:size(topology, 1)
                % DOF numbers of the start node of the i'th element
                ind1 = [(topology(i,1)*2-1):(topology(i,1)*2)];
                % DOF numbers of the end node of the i'th element
                ind2 = [(topology(i,2)*2-1):(topology(i,2)*2)];
                % Line start and end points in format [x1 y1 z1 x2 y2 z2]
                d_def(i,:)=[[d_(ind1)]', [d_(ind2)]'];
            end

            def_shape = lines + d_def;

            figure
            hold on
            axis equal
            grid on
            for i = 1:size(topology, 1)
                % Average coordinates for placing element numbers
                avcoord(i,:) = [mean(lines(i, [1, 3])), mean(lines(i, [2,4]))];

                % Plots the lines and nodes
                plot(lines(i, [1, 3]), lines(i, [2, 4]), '.-k', 'MarkerSize', 50)
                plot(def_shape(i, [1, 3]), def_shape(i, [2, 4]), '.-r', 'MarkerSize', 25)
                %% Element and node numbering
                % Plots nodal numbers for all starting nodes
                text(lines(i, 1), lines(i, 3), num2str(topology(i, 1)),'color','white',...
                    'HorizontalAlignment','center')
                % Plots nodal numbers for all ending nodes
                text(lines(i, 2), lines(i, 4), num2str(topology(i, 2)),'color','white',...
                    'HorizontalAlignment','center')
                % Plots element numbers
                text(avcoord(i,1),avcoord(i,2),num2str(i),'color','black','backgroundcolor','white')
                xlabel('x')
                ylabel('y')
                zlabel('z')
            end
        end
    end
end
