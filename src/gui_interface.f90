! Copyright (c) 2017 Alberto Otero de la Roza
! <aoterodelaroza@gmail.com>, Robin Myhr <x@example.com>, Isaac
! Visintainer <x@example.com>, Richard Greaves <x@example.com>, Ángel
! Martín Pendás <angel@fluor.quimica.uniovi.es> and Víctor Luaña
! <victor@fluor.quimica.uniovi.es>.
!
! critic2 is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or (at
! your option) any later version.
! 
! critic2 is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
! 
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.

!> Interface for the critic2 GUI.
module gui_interface
  use systemmod, only: system
  use crystalseedmod, only: crystalseed
  use iso_c_binding, only: c_ptr, c_null_ptr, c_float, c_char, c_int,&
     c_bool
  implicit none

  private

  !xx! interoperable types
  ! C-interoperable atom type
  type, bind(c) :: c_atom
     real(c_float) :: x(3) !< atom position (crystallographic) 
     real(c_float) :: r(3) !< atom position (Cartesian, bohr) 
     integer(c_int) :: is !< atom species
     integer(c_int) :: z !< atomic number
     character(kind=c_char,len=1) :: name(11) !< atomic name
     integer(c_int) :: idx !< index from the nneq list
     integer(c_int) :: cidx !< index from the complete list
     integer(c_int) :: flvec(3) !< lvec to the position in the fragment
     integer(c_int) :: ifrag !< which fragment this atom belongs to
     real(c_float) :: rad !< ball radius (bohr) 
     real(c_float) :: rgb(4) !< color (0 to 1)
     integer(c_int) :: ncon !< number of neighbors
  end type c_atom

  type scene
     integer :: isinit = 0 ! 0 = not init; 1 = seed; 2 = full
     type(crystalseed) :: seed ! crystal seed for this scene
     type(system) :: sy ! system for this scene
     real*8 :: center(3) ! center of the scene (bohr)
     real(c_float) :: srad ! radius of the encompassing sphere

     logical(c_bool) :: ismolecule ! is this a molecule?
     integer(c_int) :: nat ! number of atoms
     type(c_atom), allocatable :: at(:) ! atoms

     integer(c_int), allocatable :: idcon(:,:) !< id (cidx) of the connected atom
     integer(c_int), allocatable :: lcon(:,:,:) !< lattice vector of the connected atom

     integer(c_int) :: nmol ! number of fragments
     integer(c_int), allocatable :: moldiscrete(:) ! is fragment discrete?

     real(c_float) :: avec(3,3) ! lattice vectors
     real(c_float) :: molx0(3) ! molecule centering translation
     real(c_float) :: molborder(3) ! molecular cell
  end type scene
  integer :: nsc = 0
  type(scene), allocatable, target :: sc(:)

  !xx! public interface
  ! routines
  public :: gui_initialize
  public :: open_file
  public :: set_scene_pointers
  public :: gui_end

  ! pointers to the current scene
  integer(c_int), bind(c) :: isinit 
  real(c_float), bind(c) :: scenerad
  integer(c_int), bind(c) :: nat
  type(c_ptr), bind(c) :: at

  integer(c_int), bind(c) :: mncon
  type(c_ptr), bind(c) :: idcon
  type(c_ptr), bind(c) :: lcon

  integer(c_int), bind(c) :: nmol
  type(c_ptr), bind(c) :: moldiscrete

  type(c_ptr), bind(c) :: avec(3)
  integer(c_int), bind(c) :: ismolecule
  type(c_ptr), bind(c) :: molx0
  type(c_ptr), bind(c) :: molborder

contains

  !> Initialize the critic2 GUI.
  subroutine gui_initialize() bind(c)
    use iso_fortran_env, only: input_unit, output_unit
    use systemmod, only: systemmod_init
    use spgs, only: spgs_init
    use config, only: datadir, version, atarget, adate, f77, fflags, fc, &
       fcflags, cc, cflags, ldflags, enable_debug, package
    use global, only: global_init, config_write, initial_banner, crsmall
    use tools_io, only: ioinit, ucopy, uout, start_clock, &
       tictac, interactive, uin, filepath
    use param, only: param_init

    ! initialize parameters
    call start_clock()
    call param_init()

    ! input/output, arguments (tools_io)
    call ioinit()
    uin = input_unit
    uout = output_unit
    interactive = .false.
    filepath = "."

    ! set default values and initialize the rest of the modules
    call global_init("",datadir)
    call spgs_init()
    call systemmod_init(1)

    ! always calculate the bonds
    crsmall = huge(crsmall)

    ! banner and compilation info; do not copy input
    call initial_banner()
    call config_write(package,version,atarget,adate,f77,fflags,fc,&
       fcflags,cc,cflags,ldflags,enable_debug,datadir)
    call tictac('CRITIC2')
    write (uout,*)
    ucopy = -1

    ! allocate the initial scene
    if (allocated(sc)) deallocate(sc)
    allocate(sc(1))
    nsc = 0
    isinit = 0
    scenerad = 10._c_float

  end subroutine gui_initialize

  !> Open one or more scenes from all files in the line. ismolecule: 0
  !> = crystal, 1 = molecule, -1 = critic2 decides.
  subroutine open_file(line0,ismolecule) bind(c)
    use c_interface_module, only: c_string_value, f_c_string
    use iso_c_binding, only: c_int
    use crystalseedmod, only: read_seeds_from_file, crystalseed
    use tools_math, only: norm
    use param, only: pi, atmcov, jmlcol
    type(c_ptr), intent(in) :: line0
    integer(c_int), value :: ismolecule

    integer :: lp
    character(len=:), allocatable :: line
    integer :: i, j, idx, iz, nseed, n, idx1, idx2, iz1, iz2, is
    type(crystalseed), allocatable :: seed(:)
    real(c_float) :: xmin(3), xmax(3)
    real*8 :: dist
    integer :: mncon_

    ! transform to fortran string
    line = c_string_value(line0)
    
    ! read all seeds from the line
    lp = 1
    call read_seeds_from_file(line,lp,ismolecule,nseed,seed)
    
    if (nseed > 0) then
       ! initialize the system from the first seed
       nsc = 1
       sc(1)%seed = seed(1)
       sc(1)%isinit = 2
       call sc(1)%sy%new_from_seed(sc(1)%seed)
       call sc(1)%sy%report(.true.,.true.,.true.,.true.,.true.,.true.,.false.)
       sc(1)%center = 0d0

       ! build the atom list
       mncon_ = 0
       sc(1)%nat = sc(1)%sy%c%ncel
       if (allocated(sc(1)%at)) deallocate(sc(1)%at)
       allocate(sc(1)%at(sc(1)%nat))
       do i = 1, sc(1)%nat
          is = sc(1)%sy%c%atcel(i)%is
          idx = sc(1)%sy%c%atcel(i)%idx
          iz = sc(1)%sy%c%spc(is)%z

          sc(1)%at(i)%x = sc(1)%sy%c%atcel(i)%x
          sc(1)%at(i)%r = sc(1)%sy%c%atcel(i)%r
          sc(1)%at(i)%is = is
          sc(1)%at(i)%idx = idx
          sc(1)%at(i)%cidx = i
          sc(1)%at(i)%z = iz
          call f_c_string(sc(1)%sy%c%spc(is)%name,sc(1)%at(i)%name,11)
          sc(1)%at(i)%ncon = sc(1)%sy%c%nstar(i)%ncon
          mncon_ = max(mncon_,sc(1)%at(i)%ncon)

          if (atmcov(iz) > 1) then
             sc(1)%at(i)%rad = 0.7*atmcov(iz)
          else
             sc(1)%at(i)%rad = 1.5*atmcov(iz)
          end if
          sc(1)%at(i)%rgb(1:3) = real(jmlcol(:,iz),4) / 255.
          sc(1)%at(i)%rgb(4) = 1.0
       end do

       ! build the fragment info
       sc(1)%nmol = sc(1)%sy%c%nmol
       allocate(sc(1)%moldiscrete(sc(1)%nmol))
       do i = 1, sc(1)%sy%c%nmol
          if (sc(1)%sy%c%moldiscrete(i)) then
             sc(1)%moldiscrete(i) = 1
          else
             sc(1)%moldiscrete(i) = 0
          end if
          do j = 1, sc(1)%sy%c%mol(i)%nat
             idx = sc(1)%sy%c%mol(i)%at(j)%cidx
             sc(1)%at(idx)%flvec = sc(1)%sy%c%mol(i)%at(j)%lvec
             sc(1)%at(idx)%ifrag = i-1
          end do
       end do

       ! build the neighbor info
       allocate(sc(1)%idcon(mncon_,sc(1)%nat))
       allocate(sc(1)%lcon(3,mncon_,sc(1)%nat))
       sc(1)%idcon = 0
       sc(1)%lcon = 0
       do i = 1, sc(1)%nat
          do j = 1, sc(1)%at(i)%ncon
             sc(1)%idcon(j,i) = sc(1)%sy%c%nstar(i)%idcon(j)-1
             sc(1)%lcon(:,j,i) = sc(1)%sy%c%nstar(i)%lcon(:,j)
          end do
       end do

       ! calculate the scene radius
       if (sc(1)%nat > 0) then
          xmin = sc(1)%at(1)%r
          xmax = sc(1)%at(1)%r
          do i = 2, sc(1)%nat
             xmax = max(sc(1)%at(i)%r,xmax)
             xmin = min(sc(1)%at(i)%r,xmin)
          end do
       else
          xmin = 0._c_float
          xmax = 0._c_float
       end if
       sc(1)%srad = max(sqrt(dot_product(xmax-xmin,xmax-xmin)),0.1_c_float)

       ! lattice vectors
       sc(1)%avec = sc(1)%sy%c%crys2car
       sc(1)%ismolecule = sc(1)%sy%c%ismolecule
       sc(1)%molx0 = sc(1)%sy%c%molx0
       sc(1)%molborder = sc(1)%sy%c%molborder
    end if

  end subroutine open_file

  subroutine set_scene_pointers(isc) bind(c)
    use iso_c_binding, only: c_loc
    integer(c_int), value, intent(in) :: isc

    nat = 0
    isinit = 0
    if (isc < 0 .or. isc > nsc) return

    isinit = sc(isc)%isinit
    scenerad = sc(isc)%srad

    nat = sc(isc)%nat
    at = c_loc(sc(isc)%at)

    mncon = size(sc(isc)%idcon,1)
    idcon = c_loc(sc(isc)%idcon)
    lcon = c_loc(sc(isc)%lcon)

    nmol = sc(isc)%nmol
    moldiscrete = c_loc(sc(isc)%moldiscrete)

    avec(1) = c_loc(sc(isc)%avec(1,1))
    avec(2) = c_loc(sc(isc)%avec(1,2))
    avec(3) = c_loc(sc(isc)%avec(1,3))
    if (sc(isc)%ismolecule) then
       ismolecule = 1
    else
       ismolecule = 0
    end if
    molx0 = c_loc(sc(isc)%molx0)
    molborder = c_loc(sc(isc)%molborder)

  end subroutine set_scene_pointers

  subroutine gui_end() bind(c)
    use grid1mod, only: grid1_clean_grids
    use tools_io, only: print_clock, tictac, ncomms, nwarns, uout, string

    ! deallocate scene
    if (allocated(sc)) deallocate(sc)
    nsc = 0

    ! kill atomic grids
    call grid1_clean_grids()
    
    ! final message
    write (uout,'("CRITIC2 ended succesfully (",A," WARNINGS, ",A," COMMENTS)"/)')&
       string(nwarns), string(ncomms)
    call print_clock()
    call tictac('CRITIC2')
    
  end subroutine gui_end

end module gui_interface
