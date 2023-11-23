%% Generate a beam element model
FE = FiniteElementModel();

FE.from_xlsx('structures/lecture_7.xlsx');

%% Assemble system matrices
FE.assembly("beam", [1, 2, 3, 37, 38, 39]);
alpha = 0.01;
beta = 0.001;
FE.Cg = alpha * FE.Mg + beta * FE.Kg


%% Optionally ploy the structure
plotmesh(FE.mesh)


%% Generate strain interpolation matrix
n_el = size(FE.mesh.topology, 1);

% Define array of time steps
t = linspace(0, 100);

% Define loads
F = []

% Define initial conditions
x0 = zeros(FE.n_dof, 1);
v0 = zeros(FE.n_dof, 1);
a0 = zeros(FE.n_dof, 1);

% Define integration parameters
beta = 1 / 4;
gamma = 1 / 2;

%% Simulate time domain response
% Outputs:
%   x: displacement history
%   v: velocity history
%   a: acceleration history

[x, v, a] = newmark(FE.Kg, FE.Cg, FE.Mg, t, F, x0, v0, beta, gamma)
