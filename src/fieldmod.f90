! Copyright (c) 2015 Alberto Otero de la Roza <aoterodelaroza@gmail.com>,
! Ángel Martín Pendás <angel@fluor.quimica.uniovi.es> and Víctor Luaña
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

!> Field class
module fieldmod
  use crystalmod, only: crystal
  use fragmentmod, only: fragment
  use elk_private, only: elkwfn
  use wien_private, only: wienwfn
  use pi_private, only: piwfn
  use grid3mod, only: grid3
  use wfn_private, only: molwfn
  use dftb_private, only: dftbwfn
  use param, only: maxzat0
  use types, only: cp_type
  use hashmod, only: hash
  implicit none
  
  private

  public :: realloc_field
  private :: adaptive_stepper
  private :: stepper_euler1
  private :: stepper_heun
  private :: stepper_bs
  private :: stepper_rkck
  private :: stepper_dp
  public :: prunepath

  ! pointers for the arithmetic module
  interface
     !> Check that the id is a grid and is a sane field
     function fcheck(id,iout)
       logical :: fcheck
       character*(*), intent(in) :: id
       integer, intent(out), optional :: iout
     end function fcheck
     !> Evaluate the field at a point
     function feval(id,nder,x0,periodic)
       use types, only: scalar_value
       type(scalar_value) :: feval
       character*(*), intent(in) :: id
       integer, intent(in) :: nder
       real*8, intent(in) :: x0(3)
       logical, intent(in), optional :: periodic
     end function feval
  end interface

  !> Scalar field types
  integer, parameter, public :: type_uninit = -1 !< uninitialized
  integer, parameter, public :: type_promol = 0 !< promolecular density
  integer, parameter, public :: type_grid = 1 !< grid format
  integer, parameter, public :: type_wien = 2 !< wien2k format
  integer, parameter, public :: type_elk  = 3 !< elk format
  integer, parameter, public :: type_pi   = 4 !< pi format
  integer, parameter, public :: type_wfn  = 6 !< molecular wavefunction format
  integer, parameter, public :: type_dftb = 7 !< DFTB+ wavefunction
  integer, parameter, public :: type_promol_frag = 8 !< promolecular density from a fragment
  integer, parameter, public :: type_ghost = 9 !< a ghost field

  !> Definition of the field class
  type field
     ! parent structure information
     type(crystal), pointer :: c => null() !< crsytal
     integer :: id !< field ID
     ! general information
     logical :: isinit = .false. !< is this field initialized?
     integer :: type = type_uninit !< field type
     logical :: usecore = .false. !< augment with core densities
     logical :: numerical = .false. !< numerical derivatives
     logical :: exact = .false. !< exact or approximate calc
     integer :: typnuc = -3 !< type of nuclei
     character*(255) :: name = "" !< field name
     character*(255) :: file = "" !< file name
     ! scalar field types
     type(elkwfn) :: elk
     type(wienwfn) :: wien
     type(piwfn) :: pi
     type(grid3) :: grid
     type(molwfn) :: wfn
     type(dftbwfn) :: dftb
     ! promolecular and core densities
     type(fragment) :: fr
     integer :: zpsp(maxzat0)
     ! ghost field
     character*(2048) :: expr
     type(hash), pointer :: fh => null()
     procedure(fcheck), pointer, nopass :: fcheck => null()
     procedure(feval), pointer, nopass :: feval => null()
     ! critical point list
     integer :: ncp = 0
     type(cp_type), allocatable :: cp(:)
     integer :: ncpcel = 0
     type(cp_type), allocatable :: cpcel(:)
   contains
     procedure :: end => field_end !< Deallocate data and uninitialize
     procedure :: set_default_options => field_set_default_options !< Sets field default options
     procedure :: set_options => field_set_options !< Set field options from a command string
     procedure :: field_new !< Creates a new field from a field seed.
     procedure :: load_promolecular !< Loads a promolecular density field
     procedure :: load_as_fftgrid !< Loads as a transformation of a 3d grid
     procedure :: load_ghost !< Loads a ghost field
     procedure :: grd !< Calculate field value and its derivatives at a point
     procedure :: grd0 !< Calculate only the field value at a given point
     procedure :: der1i !< Numerical first derivatives of the field
     procedure :: der2ii !< Numerical second derivatives (diagonal)
     procedure :: der2ij !< Numerical second derivatives (mixed)
     procedure :: typestring !< Return a string identifying the field type
     procedure :: printinfo !< Print field information to stdout
     procedure :: init_cplist !< Initialize the CP list
     procedure :: nearest_cp !< Given a point, find the nearest CP of a certain type
     procedure :: identify_cp !< Identify the CP given the position
     procedure :: testrmt !< Test for MT discontinuities
     procedure :: benchmark !< Test the speed of field evaluation
     procedure :: newton !< Newton-Raphson search for a CP
     procedure :: gradient !< Calculate a gradient path
  end type field 
  public :: field

  ! eps to move to the main cell
  real*8, parameter :: flooreps = 1d-4 ! border around unit cell

  ! numerical differentiation parameters
  real*8, parameter :: derw = 1.4d0, derw2 = derw*derw, big = 1d30, safe = 2d0
  integer, parameter :: ndif_jmax = 10

contains
  
  !> Adapt the size of an allocatable 1D type(field) array
  subroutine realloc_field(a,nnew)
    use tools_io, only: ferror, faterr

    type(field), intent(inout), allocatable :: a(:)
    integer, intent(in) :: nnew

    type(field), allocatable :: temp(:)
    integer :: l1, u1

    if (.not.allocated(a)) &
       call ferror('realloc_field','array not allocated',faterr)
    l1 = lbound(a,1)
    u1 = ubound(a,1)
    if (u1 == nnew) return
    allocate(temp(l1:nnew))

    temp(l1:min(nnew,u1)) = a(l1:min(nnew,u1))
    call move_alloc(temp,a)

  end subroutine realloc_field

  !> Deallocate and uninitialize
  subroutine field_end(f)
    class(field), intent(inout) :: f

    nullify(f%c)
    f%isinit = .false.
    f%type = type_uninit
    f%usecore = .false.
    f%numerical = .false.
    f%exact = .false.
    f%typnuc = -3
    f%name = ""
    f%file = ""
    call f%elk%end()
    call f%wien%end()
    call f%pi%end()
    call f%grid%end()
    call f%wfn%end()
    call f%dftb%end()
    f%zpsp = -1
    f%expr = ""
    nullify(f%fh)
    nullify(f%fcheck)
    nullify(f%feval)
    call f%fr%init()
    if (allocated(f%cp)) deallocate(f%cp)
    if (allocated(f%cpcel)) deallocate(f%cpcel)
    f%ncp = 0
    f%ncpcel = 0

  end subroutine field_end

  !> Sets the default options for the given field.
  subroutine field_set_default_options(ff)
    class(field), intent(inout) :: ff
    
    call ff%grid%setmode('default')
    ff%exact = .false.
    ff%wien%cnorm = .true.
    ff%usecore = .false.
    ff%numerical = .false.
    ff%typnuc = -3
    ff%zpsp = -1

  end subroutine field_set_default_options

  !> Set field flags. fid is the field slot. line is the input line to
  !> parse. oksyn is true in output if the syntax was OK. dormt is
  !> true in output if the MT test discontinuity test needs to be run
  !> for elk/wien2k fields.
  subroutine field_set_options(ff,line,errmsg)
    use grid1mod, only: grid1_register_core
    use global, only: eval_next
    use tools_io, only: string, lgetword, equal, isexpression_or_word, zatguess,&
       isinteger, getword
    use param, only: sqfp
    use hashmod, only: hash
    class(field), intent(inout) :: ff
    character*(*), intent(in) :: line
    character(len=:), allocatable, intent(out) :: errmsg

    character(len=:), allocatable :: word, word2, aux
    integer :: lp, lp2, iz, iq
    logical :: ok
    real*8 :: norm

    errmsg = ""
    ! parse the rest of the line
    lp = 1
    do while (.true.)
       word = lgetword(line,lp)
       if (equal(word,'tricubic') .or. equal(word,'trispline') .or. &
           equal(word,'trilinear') .or. equal(word,'nearest')) then
          call ff%grid%setmode(word)
       else if (equal(word,'exact')) then
          ff%exact = .true.
       else if (equal(word,'approximate')) then
          ff%exact = .false.
       else if (equal(word,'rhonorm')) then
          if (.not.ff%type == type_wien) then
             errmsg = "rhonorm incompatible with fields other than wien2k"
             return
          end if
          if (.not.ff%wien%cnorm) then
             ff%wien%cnorm = .true.
             if (allocated(ff%wien%slm)) &
                ff%wien%slm(:,1,:) = ff%wien%slm(:,1,:) / sqfp
          end if
       else if (equal(word,'vnorm')) then
          if (.not.ff%type == type_wien) then
             errmsg = "vnorm incompatible with fields other than wien2k"
             return
          end if
          if (ff%wien%cnorm) then
             ff%wien%cnorm = .false.
             if (allocated(ff%wien%slm)) &
                ff%wien%slm(:,1,:) = ff%wien%slm(:,1,:) * sqfp
          end if
       else if (equal(word,'core')) then
          ff%usecore = .true.
       else if (equal(word,'nocore')) then
          ff%usecore = .false.
       else if (equal(word,'numerical')) then
          ff%numerical = .true.
       else if (equal(word,'analytical')) then
          ff%numerical = .false.
       else if (equal(word,'typnuc')) then
          ok = eval_next(ff%typnuc,line,lp)
          if (.not.ok) then
             errmsg = "wrong typnuc"
             return
          end if
          if (ff%typnuc /= -3 .and. ff%typnuc /= -1 .and. &
              ff%typnuc /= +1 .and. ff%typnuc /= +3) then
             errmsg = "wrong typnuc"
             return
          end if
       else if (equal(word,'normalize')) then
          if (.not.ff%type == type_grid) then
             errmsg = "vnorm incompatible with fields other than grids"
             return
          end if
          ok = eval_next(norm,line,lp)
          if (.not. ok) then
             errmsg = "value for normalize keyword missing"
             return
          end if
          call ff%grid%normalize(norm,ff%c%omega)
       else if (equal(word,'zpsp')) then
          do while (.true.)
             lp2 = lp
             word2 = getword(line,lp)
             if (len_trim(word2) > 0 .and. len_trim(word2) <= 2) then
                iz = zatguess(word2) 
                if (iz > 0) then
                   aux = getword(line,lp)
                   if (.not.isinteger(iq,aux)) then
                      errmsg = "wrong syntax in ZPSP"
                      return
                   end if
                   ff%zpsp(iz) = iq
                   call grid1_register_core(iz,iq)
                else
                   lp = lp2
                   exit
                end if
             else
                lp = lp2
                exit
             end if
          end do
          
       else if (len_trim(word) > 0) then
          errmsg = "unknown extra keyword"
          return
       else
          exit
       end if
    end do

  end subroutine field_set_options

  !> Load a new field using the given field seed and the crystal
  !> structure pointer. The ID of the field in the system is also
  !> required.
  subroutine field_new(f,seed,c,id,fh,fcheck,feval,errmsg)
    use types, only: realloc
    use fieldseedmod, only: fieldseed
    use arithmetic, only: eval
    use param, only: ifformat_unknown, ifformat_wien, ifformat_elk, ifformat_pi,&
       ifformat_cube, ifformat_abinit, ifformat_vasp, ifformat_vaspchg, ifformat_qub,&
       ifformat_xsf, ifformat_elkgrid, ifformat_siestagrid, ifformat_dftb, ifformat_chk,&
       ifformat_wfn, ifformat_wfx, ifformat_fchk, ifformat_molden, ifformat_as,&
       ifformat_as_promolecular, ifformat_as_core, ifformat_as_lap, ifformat_as_grad,&
       ifformat_as_clm, ifformat_as_clm_sub, ifformat_as_ghost, ifformat_copy,&
       ifformat_promolecular, ifformat_promolecular_fragment
    use hashmod, only: hash
    class(field), intent(inout) :: f !< Input field
    type(fieldseed), intent(in) :: seed 
    type(crystal), intent(in), target :: c
    integer, intent(in) :: id
    type(hash), intent(in) :: fh
    character(len=:), allocatable, intent(out) :: errmsg

    interface
       !> Check that the id is a grid and is a sane field
       function fcheck(id,iout)
         logical :: fcheck
         character*(*), intent(in) :: id
         integer, intent(out), optional :: iout
       end function fcheck
       !> Evaluate the field at a point
       function feval(id,nder,x0,periodic)
         use types, only: scalar_value
         type(scalar_value) :: feval
         character*(*), intent(in) :: id
         integer, intent(in) :: nder
         real*8, intent(in) :: x0(3)
         logical, intent(in), optional :: periodic
       end function feval
    end interface

    character(len=:), allocatable :: ofile
    integer :: i, j, k, iz, n(3)
    type(fragment) :: fr
    real*8 :: xdelta(3,3), x(3), rho
    logical :: iok

    errmsg = ""
    if (.not.c%isinit) then
       errmsg = "crystal not initialized"
       return
    end if
    call f%end()
    f%c => c
    f%id = id
    f%name = adjustl(trim(seed%fid))

    ! set the default field flags
    call f%set_default_options()

    ! inherit the pseudopotential charges from the crystal
    f%zpsp = c%zpsp

    ! interpret the seed and load the field
    if (seed%iff == ifformat_unknown) then
       errmsg = "unknown seed format"
       call f%end()
       return

    elseif (seed%iff == ifformat_wien) then
       call f%wien%end()
       call f%wien%read_clmsum(seed%file(1),seed%file(2))
       f%type = type_wien
       f%file = seed%file(1)

    elseif (seed%iff == ifformat_elk) then
       if (seed%nfile == 1) then
          call f%grid%end()
          call f%grid%read_elk(seed%file(1))
          f%type = type_grid
          f%file = seed%file(1)
       elseif (seed%nfile == 2) then
          call f%elk%end()
          call f%elk%read_out(seed%file(1),seed%file(2))
          f%type = type_elk
          f%file = seed%file(1)
       else
          call f%elk%end()
          call f%elk%read_out(seed%file(1),seed%file(2),seed%file(3))
          f%type = type_elk
          f%file = seed%file(3)
       endif

    elseif (seed%iff == ifformat_pi) then
       call f%pi%end()
       do i = 1, seed%nfile
          if (seed%piat(i) > 0) then
             iz = seed%piat(i)
          else
             iz = abs(seed%piat(i))
             if (iz < 1 .or. iz > c%nneq) then
                errmsg = "invalid non-equivalent atom number in pi load"
                call f%end()
                return
             end if
             iz = f%c%at(iz)%z
          endif
          do j = 1, f%c%nneq
             if (iz == f%c%at(j)%z) &
                call f%pi%read_ion(seed%file(i),j)
          end do
       end do
       call f%pi%register_struct(f%c%nenv,f%c%at,f%c%atenv(1:f%c%nenv))
       call f%pi%fillinterpol()
       f%type = type_pi
       f%file = "<pi ion files>"

    elseif (seed%iff == ifformat_cube) then
       call f%grid%end()
       call f%grid%read_cube(seed%file(1))
       f%type = type_grid
       f%file = seed%file(1)

    elseif (seed%iff == ifformat_abinit) then
       call f%grid%end()
       call f%grid%read_abinit(seed%file(1))
       f%type = type_grid
       f%file = seed%file(1)

    elseif (seed%iff == ifformat_vasp) then
       call f%grid%end()
       call f%grid%read_vasp(seed%file(1),f%c%omega)
       f%type = type_grid
       f%file = seed%file(1)

    elseif (seed%iff == ifformat_vaspchg) then
       call f%grid%end()
       call f%grid%read_vasp(seed%file(1),1d0)
       f%type = type_grid
       f%file = seed%file(1)

    elseif (seed%iff == ifformat_qub) then
       call f%grid%end()
       call f%grid%read_qub(seed%file(1))
       f%type = type_grid
       f%file = seed%file(1)

    elseif (seed%iff == ifformat_xsf) then
       call f%grid%end()
       call f%grid%read_xsf(seed%file(1))
       f%type = type_grid
       f%file = seed%file(1)

    elseif (seed%iff == ifformat_elkgrid) then
       call f%grid%end()
       call f%grid%read_elk(seed%file(1))
       f%type = type_grid
       f%file = seed%file(1)

    elseif (seed%iff == ifformat_siestagrid) then
       call f%grid%end()
       call f%grid%read_siesta(seed%file(1))
       f%type = type_grid
       f%file = seed%file(1)

    elseif (seed%iff == ifformat_dftb) then
       call f%dftb%end()
       call f%dftb%read(seed%file(1),seed%file(2),seed%file(3),f%c%atcel(1:f%c%ncel),f%c%at(1:f%c%nneq))
       call f%dftb%register_struct(f%c%crys2car,f%c%atenv(1:f%c%nenv),f%c%at(1:f%c%nneq))
       f%type = type_dftb
       f%file = seed%file(1)

    elseif (seed%iff == ifformat_chk) then
       call f%grid%end()

       if (seed%nfile == 1) then
          ofile = ""
       else
          ofile = seed%file(2)
       end if
       if (len_trim(seed%unkgen) > 0 .and. len_trim(seed%evc) > 0) then
          call f%grid%read_unkgen(seed%file(1),ofile,seed%unkgen,seed%evc,&
             f%c%omega,seed%sijchk)
       else
          call f%grid%read_unk(seed%file(1),ofile,f%c%omega,seed%nou,&
             seed%sijchk)
       end if
       f%grid%wan%useu = .not.seed%nou
       f%grid%wan%sijchk = seed%sijchk
       f%grid%wan%fachk = seed%fachk
       f%grid%wan%haschk = .false.
       f%grid%wan%cutoff = seed%wancut
       f%type = type_grid
       f%file = trim(seed%file(1))

    elseif (seed%iff == ifformat_wfn) then
       call f%wfn%end()
       call f%wfn%read_wfn(seed%file(1))
       call f%wfn%register_struct(f%c%ncel,f%c%atcel)
       f%type = type_wfn
       f%file = trim(seed%file(1))

    elseif (seed%iff == ifformat_wfx) then
       call f%wfn%end()
       call f%wfn%read_wfx(seed%file(1))
       call f%wfn%register_struct(f%c%ncel,f%c%atcel)
       f%type = type_wfn
       f%file = trim(seed%file(1))

    elseif (seed%iff == ifformat_fchk) then
       call f%wfn%end()
       call f%wfn%read_fchk(seed%file(1))
       call f%wfn%register_struct(f%c%ncel,f%c%atcel)
       f%type = type_wfn
       f%file = trim(seed%file(1))

    elseif (seed%iff == ifformat_molden) then
       call f%wfn%end()
       call f%wfn%read_molden(seed%file(1))
       call f%wfn%register_struct(f%c%ncel,f%c%atcel)
       f%type = type_wfn
       f%file = trim(seed%file(1))

    elseif (seed%iff == ifformat_promolecular) then
       call f%load_promolecular(f%c,id,"<promolecular>")

    elseif (seed%iff == ifformat_promolecular_fragment) then
       fr = f%c%identify_fragment_from_xyz(seed%file(1))
       if (fr%nat == 0) then
          errmsg = "fragment contains unknown atoms"
          call f%end()
          return
       end if
       call f%load_promolecular(f%c,id,trim(seed%file(1)),fr)

    elseif (seed%iff == ifformat_as_promolecular.or.seed%iff == ifformat_as_core) then
       if (seed%iff == ifformat_as_promolecular) then
          if (seed%nfile > 0) then
             fr = c%identify_fragment_from_xyz(seed%file(1))
             if (fr%nat == 0) then
                errmsg = "zero atoms in the fragment"
                call f%end()
                return
             end if
             call c%promolecular_grid(f%grid,seed%n,fr=fr)
          else
             call c%promolecular_grid(f%grid,seed%n)
          end if
       else
          call c%promolecular_grid(f%grid,seed%n,zpsp=c%zpsp)
       end if
       f%type = type_grid
       f%file = ""

    elseif (seed%iff == ifformat_as_ghost) then
       call f%load_ghost(c,id,"<ghost>",seed%expr,fh,fcheck,feval)
       
    elseif (seed%iff == ifformat_as) then
       call f%grid%end()
       f%type = type_grid
       f%file = ""
       n = seed%n
       f%grid%n = n
       allocate(f%grid%f(n(1),n(2),n(3)))
       
       do i = 1, 3
          xdelta(:,i) = 0d0
          xdelta(i,i) = 1d0 / real(n(i),8)
       end do

       !$omp parallel do private(x,rho) schedule(dynamic)
       do k = 1, n(3)
          do j = 1, n(2)
             do i = 1, n(1)
                x = (i-1) * xdelta(:,1) + (j-1) * xdelta(:,2) + (k-1) * xdelta(:,3)
                x = c%x2c(x)
                rho = eval(seed%expr,.true.,iok,x,fh,fcheck,feval,.true.)
                !$omp critical(write)
                f%grid%f(i,j,k) = rho
                !$omp end critical(write)
             end do
          end do
       end do
       !$omp end parallel do
       f%grid%init = .true.

    elseif (seed%iff == ifformat_copy .or. seed%iff == ifformat_as_lap .or.&
       seed%iff == ifformat_as_grad.or.seed%iff == ifformat_as_clm.or.&
       seed%iff == ifformat_as_clm_sub) then
       errmsg = "error in file format for field_new"
       call f%end()
       return
    else
       errmsg = "unknown seed format"
       call f%end()
       return
    end if

    ! set the rest of the variables passed with the field
    call f%set_options(seed%elseopt,errmsg)
    if (len_trim(errmsg) > 0) then
       call f%end()
       return
    end if

    f%isinit = .true.
    call f%init_cplist()
    
  end subroutine field_new

  !> Load a promolecular density field using the given crystal
  !> structure. The ID and name of the field are also set using
  !> the provided arguments.
  subroutine load_promolecular(f,c,id,name,fr)
    use fragmentmod, only: fragment
    class(field), intent(inout) :: f !< Input field
    type(crystal), intent(in), target :: c
    integer, intent(in) :: id
    character*(*), intent(in) :: name
    type(fragment), intent(in), optional :: fr

    if (.not.c%isinit) return
    call f%end()
    f%c => c
    f%id = id
    f%isinit = .true.
    if (present(fr)) then
       f%type = type_promol_frag
       f%fr = fr
    else
       f%type = type_promol
    end if
    f%usecore = .false. 
    f%numerical = .false. 
    f%exact = .false. 
    f%name = adjustl(name)
    f%file = ""
    f%typnuc = -3
    f%zpsp = c%zpsp
    call f%init_cplist()
    
  end subroutine load_promolecular

  !> Load field as a transformation of the 3d grid given in g. ityp:
  !> type of transformation to perform (uses the ifformat
  !> flags). Available: Laplacian and gradient.
  subroutine load_as_fftgrid(f,c,id,name,g,ityp)
    use grid3mod, only: grid3
    use fragmentmod, only: fragment
    use param, only: ifformat_as_lap, ifformat_as_grad, ifformat_as_hxx1,&
       ifformat_as_hxx2, ifformat_as_hxx3
    class(field), intent(inout) :: f !< Input/output field
    type(crystal), intent(in), target :: c
    integer, intent(in) :: id
    character*(*), intent(in) :: name
    type(grid3), intent(in) :: g
    integer, intent(in) :: ityp

    if (.not.c%isinit) return
    call f%end()
    f%c => c
    f%id = id
    f%isinit = .true.
    f%type = type_grid
    if (ityp == ifformat_as_lap) then
       call f%grid%laplacian(g,c%crys2car)
    elseif (ityp == ifformat_as_grad) then
       call f%grid%gradrho(g,c%crys2car)
    elseif (ityp == ifformat_as_hxx1) then
       call f%grid%hxx(g,1,c%crys2car)
    elseif (ityp == ifformat_as_hxx2) then
       call f%grid%hxx(g,2,c%crys2car)
    elseif (ityp == ifformat_as_hxx3) then
       call f%grid%hxx(g,3,c%crys2car)
    end if
    f%usecore = .false. 
    f%numerical = .false. 
    f%exact = .false. 
    f%name = adjustl(name)
    f%file = ""
    f%typnuc = -3
    f%zpsp = c%zpsp
    call f%init_cplist()
    
  end subroutine load_as_fftgrid

  !> Load a ghost field.
  subroutine load_ghost(f,c,id,name,expr,fh,fcheck,feval)
    use grid3mod, only: grid3
    use fragmentmod, only: fragment
    use hashmod, only: hash
    class(field), intent(inout) :: f !< Input/output field
    type(crystal), intent(in), target :: c
    integer, intent(in) :: id
    character*(*), intent(in) :: name
    character*(*), intent(in) :: expr
    type(hash), intent(in), target :: fh 
    interface
       !> Check that the id is a grid and is a sane field
       function fcheck(id,iout)
         logical :: fcheck
         character*(*), intent(in) :: id
         integer, intent(out), optional :: iout
       end function fcheck
       !> Evaluate the field at a point
       function feval(id,nder,x0,periodic)
         use types, only: scalar_value
         type(scalar_value) :: feval
         character*(*), intent(in) :: id
         integer, intent(in) :: nder
         real*8, intent(in) :: x0(3)
         logical, intent(in), optional :: periodic
       end function feval
    end interface

    if (.not.c%isinit) return
    call f%end()
    f%c => c
    f%id = id
    f%isinit = .true.
    f%type = type_ghost
    f%usecore = .false. 
    f%numerical = .true. 
    f%exact = .false. 
    f%name = adjustl(name)
    f%file = ""
    f%zpsp = c%zpsp
    f%expr = expr
    f%fh => fh
    f%fcheck => fcheck
    f%feval => feval
    call f%init_cplist()
    
  end subroutine load_ghost

  !> Calculate the scalar field f at point v (Cartesian) and its
  !> derivatives up to nder. Return the results in res0 or
  !> res0_noalloc. If periodic is present and false, consider the
  !> field is defined in a non-periodic system. This routine is
  !> thread-safe.
  recursive subroutine grd(f,v,nder,periodic,res0,res0_noalloc)
    use arithmetic, only: eval
    use types, only: scalar_value, scalar_value_noalloc
    use tools_io, only: ferror, faterr
    use tools_math, only: norm
    class(field), intent(inout) :: f !< Input field
    real*8, intent(in) :: v(3) !< Target point in Cartesian coordinates 
    integer, intent(in) :: nder !< Number of derivatives to calculate
    logical, intent(in), optional :: periodic !< Whether the system is to be considered periodic (molecules only)
    type(scalar_value), intent(out), optional :: res0 !< Output density and related scalar properties
    type(scalar_value_noalloc), intent(out), optional :: res0_noalloc !< Output density and related scalar properties (no allocatable components)

    real*8 :: wx(3), wc(3), dist, x(3)
    integer :: i, nid, lvec(3), idx(3)
    real*8 :: rho, grad(3), h(3,3)
    real*8 :: fval(-ndif_jmax:ndif_jmax,3), fzero
    logical :: isgrid, iok, per
    type(scalar_value) :: res

    real*8, parameter :: hini = 1d-3, errcnv = 1d-8
    real*8, parameter :: neargrideps = 1d-12

    if (.not.f%isinit) call ferror("grd","field not initialized",faterr)

    ! initialize output quantities 
    res%f = 0d0
    res%fval = 0d0
    res%gf = 0d0
    res%hf = 0d0
    res%gfmod = 0d0
    res%gfmodval = 0d0
    res%del2f = 0d0
    res%del2fval = 0d0
    res%gkin = 0d0
    res%vir = 0d0
    res%stress = 0d0
    res%isnuc = .false.

    ! initialize flags
    if (present(periodic)) then
       per = periodic
    else
       per = .true.
    end if

    ! numerical derivatives
    res%isnuc = .false.
    if (f%numerical) then
       fzero = grd0(f,v,periodic)
       res%f = fzero
       res%gf = 0d0
       res%hf = 0d0
       if (nder > 0) then
          ! x
          fval(:,1) = 0d0
          fval(0,1) = fzero
          res%gf(1) = f%der1i((/1d0,0d0,0d0/),v,hini,errcnv,fval(:,1),periodic)
          ! y
          fval(:,2) = 0d0
          fval(0,2) = fzero
          res%gf(2) = f%der1i((/0d0,1d0,0d0/),v,hini,errcnv,fval(:,2),periodic)
          ! z
          fval(:,3) = 0d0
          fval(0,3) = fzero
          res%gf(3) = f%der1i((/0d0,0d0,1d0/),v,hini,errcnv,fval(:,3),periodic)
          if (nder > 1) then
             ! xx, yy, zz
             res%hf(1,1) = f%der2ii((/1d0,0d0,0d0/),v,0.5d0*hini,errcnv,fval(:,1),periodic)
             res%hf(2,2) = f%der2ii((/0d0,1d0,0d0/),v,0.5d0*hini,errcnv,fval(:,2),periodic)
             res%hf(3,3) = f%der2ii((/0d0,0d0,1d0/),v,0.5d0*hini,errcnv,fval(:,3),periodic)
             ! xy, xz, yz
             res%hf(1,2) = f%der2ij((/1d0,0d0,0d0/),(/0d0,1d0,0d0/),v,hini,hini,errcnv,periodic)
             res%hf(1,3) = f%der2ij((/1d0,0d0,0d0/),(/0d0,0d0,1d0/),v,hini,hini,errcnv,periodic)
             res%hf(2,3) = f%der2ij((/0d0,1d0,0d0/),(/0d0,0d0,1d0/),v,hini,hini,errcnv,periodic)
             ! final
             res%hf(2,1) = res%hf(1,2)
             res%hf(3,1) = res%hf(1,3)
             res%hf(3,2) = res%hf(2,3)
          end if
       end if
       res%gfmod = norm(res%gf)
       res%del2f = res%hf(1,1) + res%hf(2,2) + res%hf(3,3)
       ! valence quantities
       res%fval = res%f
       res%gfmodval = res%gfmod
       res%del2fval = res%hf(1,1) + res%hf(2,2) + res%hf(3,3)
       goto 999
    end if

    ! To the main cell. Add a small safe zone around the limits of the unit cell
    ! to prevent precision problems.
    wx = f%c%c2x(v)
    if (per) then
       do i = 1, 3
          if (wx(i) < -flooreps .or. wx(i) > 1d0+flooreps) &
             wx(i) = wx(i) - real(floor(wx(i)),8)
       end do
    else
       if (.not.f%c%ismolecule) &
          call ferror("grd","non-periodic calculation in a crystal",faterr)
       ! if outside the main cell and the field is limited to a certain region of 
       ! space, nullify the result and exit
       if ((any(wx < -flooreps) .or. any(wx > 1d0+flooreps)) .and. & 
          f%type == type_grid .or. f%type == type_wien .or. f%type == type_elk .or.&
          f%type == type_pi) then 
          goto 999
       end if
    end if
    wc = f%c%x2c(wx)

    ! type selector
    select case(f%type)
    case(type_grid)
       isgrid = .false.
       if (nder == 0) then
          ! maybe we can get the grid point directly
          x = modulo(wx,1d0) * f%grid%n
          idx = nint(x)
          isgrid = all(abs(x-idx) < neargrideps)
       end if
       if (isgrid) then
          idx = modulo(idx,f%grid%n)+1
          res%f = f%grid%f(idx(1),idx(2),idx(3))
          res%gf = 0d0
          res%hf = 0d0
       else
          call f%grid%interp(wx,res%f,res%gf,res%hf)
          res%gf = matmul(transpose(f%c%car2crys),res%gf)
          res%hf = matmul(matmul(transpose(f%c%car2crys),res%hf),f%c%car2crys)
       endif

    case(type_wien)
       call f%wien%rho2(wx,res%f,res%gf,res%hf)
       res%gf = matmul(transpose(f%c%car2crys),res%gf)
       res%hf = matmul(matmul(transpose(f%c%car2crys),res%hf),f%c%car2crys)

    case(type_elk)
       call f%elk%rho2(wx,nder,res%f,res%gf,res%hf)
       res%gf = matmul(transpose(f%c%car2crys),res%gf)
       res%hf = matmul(matmul(transpose(f%c%car2crys),res%hf),f%c%car2crys)

    case(type_pi)
       call f%pi%rho2(wc,f%exact,res%f,res%gf,res%hf)
       ! transformation not needed because of pi_register_struct:
       ! all work done in Cartesians in a finite environment.

    case(type_wfn)
       call f%wfn%rho2(wc,nder,res%f,res%gf,res%hf,res%gkin,res%vir,res%stress,res%mo)
       ! transformation not needed because all work done in Cartesians
       ! in a finite environment. wfn assumes the crystal structure
       ! resulting from load xyz/wfn/wfx (molecule at the center of 
       ! a big cube).

    case(type_dftb)
       call f%dftb%rho2(wc,f%exact,nder,res%f,res%gf,res%hf,res%gkin)
       ! transformation not needed because of dftb_register_struct:
       ! all work done in Cartesians in a finite environment.

    case(type_promol)
       call f%c%promolecular(wc,res%f,res%gf,res%hf,nder,periodic=periodic)
       ! not needed because grd_atomic uses struct.

    case(type_promol_frag)
       call f%c%promolecular(wc,res%f,res%gf,res%hf,nder,fr=f%fr,periodic=periodic)
       ! not needed because grd_atomic uses struct.

    case(type_ghost)
       res%f = eval(f%expr,.true.,iok,wc,f%fh,f%fcheck,f%feval,periodic)
       res%gf = 0d0
       res%hf = 0d0

    case default
       call ferror("grd","unknown scalar field type",faterr)
    end select

    ! save the valence-only value
    res%fval = res%f
    res%gfmodval = res%gfmod
    res%del2fval = res%hf(1,1) + res%hf(2,2) + res%hf(3,3)

    ! augment with the core if applicable
    if (f%usecore .and. any(f%zpsp /= -1)) then
       call f%c%promolecular(wc,rho,grad,h,nder,zpsp=f%zpsp,periodic=periodic)
       res%f = res%f + rho
       res%gf  = res%gf + grad
       res%hf = res%hf + h
    end if

    ! If it's on a nucleus, nullify the gradient (may not be zero in
    ! grid fields, for instance)
    nid = 0
    call f%c%nearest_atom(wx,nid,dist,lvec)
    if (per .or. .not.per .and. all(lvec == 0)) then
       res%isnuc = (dist < 1d-5)
       if (res%isnuc) res%gf = 0d0
    end if
    res%gfmod = norm(res%gf)
    res%del2f = res%hf(1,1) + res%hf(2,2) + res%hf(3,3)

999 continue
    if (present(res0)) res0 = res
    if (present(res0_noalloc)) then
       res0_noalloc%f = res%f
       res0_noalloc%fval = res%fval
       res0_noalloc%gf = res%gf
       res0_noalloc%hf = res%hf
       res0_noalloc%gfmod = res%gfmod
       res0_noalloc%gfmodval = res%gfmodval
       res0_noalloc%del2f = res%del2f
       res0_noalloc%del2fval = res%del2fval
       res0_noalloc%gkin = res%gkin
       res0_noalloc%stress = res%stress
       res0_noalloc%vir = res%vir
       res0_noalloc%hfevec = res%hfevec
       res0_noalloc%hfeval = res%hfeval
       res0_noalloc%r = res%r
       res0_noalloc%s = res%s
       res0_noalloc%isnuc = res%isnuc
    end if

  end subroutine grd

  !> Calculate only the value of the scalar field at the given point
  !> (v in Cartesian). If periodic is present and false, consider the
  !> field is defined in a non-periodic system. This routine is
  !> thread-safe.
  recursive function grd0(f,v,periodic)
    use arithmetic, only: eval
    use tools_io, only: ferror, faterr
    class(field), intent(inout) :: f
    real*8, dimension(3), intent(in) :: v !< Target point in cartesian or spherical coordinates.
    real*8 :: grd0
    logical, intent(in), optional :: periodic !< Whether the system is to be considered periodic (molecules only)

    real*8 :: wx(3), wc(3)
    integer :: i
    real*8 :: h(3,3), grad(3), rho, rhoaux, gkin, vir, stress(3,3)
    logical :: iok, per

    ! initialize 
    if (present(periodic)) then
       per = periodic
    else
       per = .true.
    end if
    grd0 = 0d0

    ! To the main cell. Add a small safe zone around the limits of the unit cell
    ! to prevent precision problems.
    wx = f%c%c2x(v)
    if (per) then
       do i = 1, 3
          if (wx(i) < -flooreps .or. wx(i) > 1d0+flooreps) &
             wx(i) = wx(i) - real(floor(wx(i)),8)
       end do
    else
       if (.not.f%c%ismolecule) &
          call ferror("grd","non-periodic calculation in a crystal",faterr)
       ! if outside the main cell and the field is limited to a certain region of 
       ! space, nullify the result and exit
       if ((any(wx < -flooreps) .or. any(wx > 1d0+flooreps)) .and. & 
          f%type == type_grid .or. f%type == type_wien .or. f%type == type_elk .or.&
          f%type == type_pi) then 
          return
       end if
    end if
    wc = f%c%x2c(wx)

    ! type selector
    select case(f%type)
    case(type_grid)
       call f%grid%interp(wx,rho,grad,h)
    case(type_wien)
       call f%wien%rho2(wx,rho,grad,h)
    case(type_elk)
       call f%elk%rho2(wx,0,rho,grad,h)
    case(type_pi)
       call f%pi%rho2(wc,f%exact,rho,grad,h)
    case(type_wfn)
       call f%wfn%rho2(wc,0,rho,grad,h,gkin,vir,stress)
    case(type_dftb)
       call f%dftb%rho2(wc,f%exact,0,rho,grad,h,gkin)
    case(type_promol)
       call f%c%promolecular(wc,rho,grad,h,0,periodic=periodic)
    case(type_promol_frag)
       call f%c%promolecular(wc,rho,grad,h,0,fr=f%fr,periodic=periodic)
    case(type_ghost)
       rho = eval(f%expr,.true.,iok,wc,f%fh,f%fcheck,f%feval,periodic)
    case default
       call ferror("grd","unknown scalar field type",faterr)
    end select

    if (f%usecore .and. any(f%zpsp /= -1)) then
       call f%c%promolecular(wc,rhoaux,grad,h,0,zpsp=f%zpsp,periodic=periodic)
       rho = rho + rhoaux
    end if
    grd0 = rho

  end function grd0

  !> Function derivative using finite differences and Richardson's
  !> extrapolation formula. This routine is thread-safe.
  function der1i(f,dir,x,h,errcnv,pool,periodic)
    class(field), intent(inout) :: f
    real*8 :: der1i
    real*8, intent(in) :: dir(3)
    real*8, intent(in) :: x(3), h, errcnv
    real*8, intent(inout) :: pool(-ndif_jmax:ndif_jmax)
    logical, intent(in), optional :: periodic

    real*8 :: err
    real*8 :: ww, hh, erract, n(ndif_jmax,ndif_jmax)
    real*8 :: f0, fp, fm
    integer :: i, j
    integer :: nh

    der1i = 0d0
    nh = 0
    hh = h
    if (pool(nh+1) == 0d0) then
       f0 = f%grd0(x+dir*hh,periodic)
       pool(nh+1) = f0
    else
       f0 = pool(nh+1)
    end if
    fp = f0
    if (pool(nh+1) == 0d0) then
       f0 = f%grd0(x-dir*hh,periodic)
       pool(-nh-1) = f0
    else
       f0 = pool(-nh-1)
    end if
    fm = f0
    n(1,1) = (fp - fm) / (hh+hh)

    err = big
    do j = 2, ndif_jmax
       hh = hh / derw
       nh = nh + 1
       if (pool(nh+1) == 0d0) then
          f0 = f%grd0(x+dir*hh,periodic)
          pool(nh+1) = f0
       else
          f0 = pool(nh+1) 
       end if
       fp = f0
       if (pool(-nh-1) == 0d0) then
          f0 = f%grd0(x-dir*hh,periodic)
          pool(-nh-1) = f0
       else
          f0 = pool(-nh-1) 
       end if
       fm = f0
       n(1,j) = (fp - fm) / (hh+hh)
       ww = derw2
       do i = 2, j
          n(i,j) = (ww*n(i-1,j)-n(i-1,j-1))/(ww-1d0)
          ww = ww * derw2
          erract = max (abs(n(i,j)-n(i-1,j)), abs(n(i,j)-n(i-1,j-1)))
          if (erract.le.err) then
             err = erract
             der1i = n(i,j)
          endif
       enddo
       if ( abs(n(j,j)-n(j-1,j-1)) .gt. safe*err .or. err .le. errcnv ) return
    enddo

  end function der1i

  !> Function second derivative using finite differences and
  !> Richardson's extrapolation formula. This routine is thread-safe.
  function der2ii(f,dir,x,h,errcnv,pool,periodic)
    class(field), intent(inout) :: f
    real*8 :: der2ii
    real*8, intent(in) :: dir(3)
    real*8, intent(in) :: x(3), h, errcnv
    real*8, intent(inout) :: pool(-ndif_jmax:ndif_jmax)
    logical, intent(in), optional :: periodic

    real*8 :: err

    real*8 :: ww, hh, erract, n(ndif_jmax, ndif_jmax)
    real*8 :: fx, fp, fm, f0
    integer :: i, j
    integer :: nh

    der2ii = 0d0
    nh = 0
    hh = h
    if (pool(nh) == 0d0) then
       f0 = f%grd0(x,periodic)
       pool(nh) = f0
    else
       f0 = pool(nh)
    end if
    fx = 2 * f0
    if (pool(nh-1) == 0d0) then
       f0 = f%grd0(x-dir*(hh+hh),periodic)
       pool(nh-1) = f0
    else
       f0 = pool(nh-1)
    end if
    fm = f0
    if (pool(nh+1) == 0d0) then
       f0 = f%grd0(x+dir*(hh+hh),periodic)
       pool(nh+1) = f0
    else
       f0 = pool(nh+1)
    end if
    fp = f0
    n(1,1) = (fp - fx + fm) / (4d0*hh*hh)
    err = big
    do j = 2, ndif_jmax
       hh = hh / derw
       nh = nh + 1
       if (pool(nh+1) == 0d0) then
          f0 = f%grd0(x-dir*(hh+hh),periodic)
          pool(nh+1) = f0
       else
          f0 = pool(nh+1)
       end if
       fm = f0
       if (pool(-nh-1) == 0d0) then
          f0 = f%grd0(x+dir*(hh+hh),periodic)
          pool(-nh-1) = f0
       else
          f0 = pool(-nh-1)
       end if
       fp = f0
       n(1,j) = (fp - fx + fm) / (4d0*hh*hh)
       ww = derw2
       erract = 0d0
       do i = 2, j
          n(i,j) = (ww*n(i-1,j)-n(i-1,j-1))/(ww-1d0)
          ww = ww * derw2
          erract = max (abs(n(i,j)-n(i-1,j)), abs(n(i,j)-n(i-1,j-1)))
          if (erract.le.err) then
             err = erract
             der2ii = n(i,j)
          endif
       enddo
       if (erract .gt. safe*err .or. err .le. errcnv) return
    enddo
    return
  end function der2ii

  !> Function mixed second derivative using finite differences and
  !> Richardson's extrapolation formula. This routine is thread-safe.
  function der2ij(f,dir1,dir2,x,h1,h2,errcnv,periodic)
    class(field), intent(inout) :: f
    real*8 :: der2ij
    real*8, intent(in) :: dir1(3), dir2(3)
    real*8, intent(in) :: x(3), h1, h2, errcnv
    logical, intent(in), optional :: periodic

    real*8 :: err, fpp, fmp, fpm, fmm, f0
    real*8 :: hh1, hh2, erract, ww
    real*8 :: n(ndif_jmax,ndif_jmax)
    integer :: i, j

    der2ij = 0d0
    hh1 = h1
    hh2 = h2
    f0 = f%grd0(x+dir1*hh1+dir2*hh2,periodic)
    fpp = f0
    f0 = f%grd0(x+dir1*hh1-dir2*hh2,periodic)
    fpm = f0
    f0 = f%grd0(x-dir1*hh1+dir2*hh2,periodic)
    fmp = f0
    f0 = f%grd0(x-dir1*hh1-dir2*hh2,periodic)
    fmm = f0
    n(1,1) = (fpp - fmp - fpm + fmm ) / (4d0*hh1*hh2)
    err = big
    do j = 2, ndif_jmax
       hh1 = hh1 / derw
       hh2 = hh2 / derw
       f0 = f%grd0(x+dir1*hh1+dir2*hh2,periodic)
       fpp = f0
       f0 = f%grd0(x+dir1*hh1-dir2*hh2,periodic)
       fpm = f0
       f0 = f%grd0(x-dir1*hh1+dir2*hh2,periodic)
       fmp = f0
       f0 = f%grd0(x-dir1*hh1-dir2*hh2,periodic)
       fmm = f0
       n(1,j) = (fpp - fmp - fpm + fmm) / (4d0*hh1*hh2)
       ww = derw2
       do i = 2, j
          n(i,j) = (ww*n(i-1,j)-n(i-1,j-1))/(ww-1d0)
          ww = ww * derw2
          erract = max (abs(n(i,j)-n(i-1,j)), abs(n(i,j)-n(i-1,j-1)))
          if (erract.le.err) then
             err = erract
             der2ij = n(i,j)
          endif
       enddo
       if ( abs(n(j,j)-n(j-1,j-1)) .gt. safe*err .or. err .le. errcnv ) return
    enddo
  end function der2ij

  !> Return a string description of the field type.
  function typestring(f,short) result(s)
    use tools_io, only: faterr, ferror
    class(field), intent(in) :: f
    character(len=:), allocatable :: s
    logical, intent(in) :: short

    if (.not.short) then
       select case (f%type)
       case (type_uninit)
          s = "not used"
       case (type_promol)
          s = "promolecular"
       case (type_grid)
          s = "grid"
       case (type_wien)
          s = "wien2k"
       case (type_elk)
          s = "elk"
       case (type_pi)
          s = "pi"
       case (type_wfn)
          s = "molecular wavefunction"
       case (type_dftb)
          s = "dftb+"
       case (type_promol_frag)
          s = "promolecular fragment"
       case (type_ghost)
          s = "ghost field"
       case default
          call ferror('typestring','unknown field type',faterr)
       end select
    else
       select case (f%type)
       case (type_uninit)
          s = "??"
       case (type_promol)
          s = "promol"
       case (type_grid)
          s = "grid"
       case (type_wien)
          s = "wien2k"
       case (type_elk)
          s = "elk"
       case (type_pi)
          s = "pi"
       case (type_wfn)
          s = "molwfn"
       case (type_dftb)
          s = "dftb+"
       case (type_promol_frag)
          s = "profrg"
       case (type_ghost)
          s = "ghost"
       case default
          call ferror('typestring','unknown field type',faterr)
       end select
    end if

  endfunction typestring

  !> Write information about the field to the standard output. If
  !> isload is true, show load-time information. If isset is true,
  !> show flags for this field.
  subroutine printinfo(f,isload,isset)
    use global, only: dunit0, iunit, iunitname0
    use tools_io, only: uout, string, ferror, faterr, ioj_center, nameguess
    use param, only: maxzat0
    class(field), intent(in) :: f
    logical, intent(in) :: isload
    logical, intent(in) :: isset

    character(len=:), allocatable :: str, aux
    integer :: i, j, k, n(3)

    ! header
    if (.not.f%isinit) then
       write (uout,'("  Not initialized ")')
       return
    end if

    ! general information about the field
    if (len_trim(f%name) > 0) &
       write (uout,'("  Name: ",A)') string(f%name)
    if (len_trim(f%file) > 0) then
       write (uout,'("  Source: ",A)') string(f%file)
    else
       write (uout,'("  Source: <generated>")')
    end if
    write (uout,'("  Type: ",A)') f%typestring(.false.)

    ! type-specific
    if (f%type == type_promol) then
       ! promolecular densities
       if (isload) then
          write (uout,'("  Atoms in the environment: ",A)') string(f%c%nenv)
       end if
    elseif (f%type == type_grid) then
       ! grids
       n = f%grid%n
       if (isload) then
          write (uout,'("  Grid dimensions : ",3(A,2X))') (string(n(j)),j=1,3)
          write (uout,'("  First elements... ",3(A,2X))') (string(f%grid%f(1,1,j),'e',decimal=12),j=1,3)
          write (uout,'("  Last elements... ",3(A,2X))') (string(f%grid%f(n(1),n(2),n(3)-2+j),'e',decimal=12),j=0,2)
          write (uout,'("  Sum of elements... ",A)') string(sum(f%grid%f(:,:,:)),'e',decimal=12)
          write (uout,'("  Sum of squares of elements... ",A)') string(sum(f%grid%f(:,:,:)**2),'e',decimal=12)
          write (uout,'("  Cell integral (grid SUM) = ",A)') &
             string(sum(f%grid%f) * f%c%omega / real(product(n),8),'f',decimal=8)
          write (uout,'("  Min: ",A)') string(minval(f%grid%f),'e',decimal=8)
          write (uout,'("  Average: ",A)') string(sum(f%grid%f) / real(product(n),8),'e',decimal=8)
          write (uout,'("  Max: ",A)') string(maxval(f%grid%f),'e',decimal=8)
       end if
       if (isset) then
          write (uout,'("  Interpolation mode (1=nearest,2=linear,3=spline,4=tricubic): ",A)') string(f%grid%mode)
       end if
    elseif (f%type == type_wien) then
       if (isload) then
          write (uout,'("  Complex?: ",L)') f%wien%cmpl
          write (uout,'("  Spherical harmonics expansion LMmax: ",A)') string(size(f%wien%lm,2))
          write (uout,'("  Max. points in radial grid: ",A)') string(size(f%wien%slm,1))
          write (uout,'("  Total number of plane waves (new/orig): ",A,"/",A)') string(f%wien%nwav), string(f%wien%lastind)
       end if
       if (isset) then
          write (uout,'("  Density-style normalization? ",L)') f%wien%cnorm
       end if
    elseif (f%type == type_elk) then
       if (isload) then
          write (uout,'("  Number of LM pairs: ",A)') string(size(f%elk%rhomt,2))
          write (uout,'("  Max. points in radial grid: ",A)') string(size(f%elk%rhomt,1))
          write (uout,'("  Total number of plane waves: ",A)') string(size(f%elk%rhok))
       end if
    elseif (f%type == type_pi) then
       if (isset) then
          write (uout,'("  Exact calculation? ",L)') f%exact
       end if
    elseif (f%type == type_wfn) then
       if (isload) then
          write (uout,'("  Number of MOs: ",A)') string(f%wfn%nmo)
          write (uout,'("  Number of primitives: ",A)') string(f%wfn%npri)
          write (uout,'("  Wavefunction type (0=closed,1=open,2=frac): ",A)') string(f%wfn%wfntyp)
          write (uout,'("  Number of EDFs: ",A)') string(f%wfn%nedf)
       end if
    elseif (f%type == type_dftb) then
       if (isload) then
          write (uout,'("  Number of states: ",A)') string(f%dftb%nstates)
          write (uout,'("  Number of spin channels: ",A)') string(f%dftb%nspin)
          write (uout,'("  Number of orbitals: ",A)') string(f%dftb%norb)
          write (uout,'("  Number of kpoints: ",A)') string(f%dftb%nkpt)
          write (uout,'("  Real wavefunction? ",L)') f%dftb%isreal
       end if
       if (isset) then
          write (uout,'("  Exact calculation? ",L)') f%exact
       end if
    elseif (f%type == type_promol_frag) then
       if (isload) then
          write (uout,'("  Number of atoms in fragment: ",A)') string(f%fr%nat)
       end if
    elseif (f%type == type_ghost) then
       write (uout,'("  Expression: ",A)') string(f%expr)
    else
       call ferror("printinfo","unknown field type",faterr)
    end if

    ! flags for any field
    if (isset) then
       write (uout,'("  Use core densities? ",L)') f%usecore
       if (any(f%zpsp > 0)) then
          str = ""
          do i = 1, maxzat0
             if (f%zpsp(i) > 0) then
                aux = str // string(nameguess(i,.true.)) // "(" // string(f%zpsp(i)) // "), "
                str = aux
             end if
          end do
          aux = str
          str = aux(1:len_trim(aux)-1)
          write (uout,'("  Core charges (ZPSP): ",A)') str
       end if
       write (uout,'("  Numerical derivatives? ",L)') f%numerical
       write (uout,'("  Nuclear CP signature: ",A)') string(f%typnuc)
    end if

    write (uout,'("  Number of non-equivalent critical points: ",A)') string(f%ncp)
    write (uout,'("  Number of critical points in the unit cell: ",A)') string(f%ncpcel)

    ! Wannier information
    if (f%grid%iswan) then
       write (uout,*)
       write (uout,'("+ Wannier functions available for this field")') 
       if (f%grid%wan%haschk) then
          write (uout,'("  Source: sij-chk checkpoint file")') 
       else
          if (allocated(f%grid%wan%ngk)) then
             write (uout,'("  Source: unkgen")') 
          else
             write (uout,'("  Source: UNK files")') 
          end if
       endif
       write (uout,'("  Real-space lattice vectors: ",3(A,X))') (string(f%grid%wan%nwan(i)),i=1,3)
       write (uout,'("  Number of bands: ",A)') string(f%grid%wan%nbnd)
       write (uout,'("  Number of spin channels: ",A)') string(f%grid%wan%nspin)
       if (f%grid%wan%cutoff > 0d0) &
          write (uout,'("  Overlap calculation distance cutoff: ",A)') string(f%grid%wan%cutoff,'f',10,4)
       write (uout,'("  List of k-points: ")')
       do i = 1, f%grid%wan%nks
          write (uout,'(4X,A,A,99(X,A))') string(i),":", (string(f%grid%wan%kpt(j,i),'f',8,4),j=1,3)
       end do
       write (uout,'("  Wannier function centers (cryst. coords.) and spreads: ")')
       write (uout,'("# bnd spin        ----  center  ----        spread(",A,")")') iunitname0(iunit)
       do i = 1, f%grid%wan%nspin
          do j = 1, f%grid%wan%nbnd
             write (uout,'(2X,99(A,X))') string(j,4,ioj_center), string(i,2,ioj_center), &
                (string(f%grid%wan%center(k,j,i),'f',10,6,4),k=1,3),&
                string(f%grid%wan%spread(j,i) * dunit0(iunit),'f',14,8,4)
          end do
       end do
    end if

  end subroutine printinfo

  !> Initialize the critical point list with the atoms in the crystal
  !> structure. 
  subroutine init_cplist(f)
    use global, only: rbetadef, atomeps
    class(field), intent(inout) :: f

    integer :: i, j

    if (.not.f%c%isinit) return

    if (allocated(f%cp)) deallocate(f%cp)
    if (allocated(f%cpcel)) deallocate(f%cpcel)
    
    !.initialize
    f%ncp = f%c%nneq
    allocate(f%cp(f%ncp))
    f%ncpcel = f%c%ncel
    allocate(f%cpcel(f%ncpcel))

    ! insert the nuclei in the list
    do i = 1, f%ncp
       f%cp(i)%x = f%c%at(i)%x - floor(f%c%at(i)%x)
       f%cp(i)%r = f%c%at(i)%r
       f%cp(i)%typ = f%typnuc
       f%cp(i)%typind = (f%cp(i)%typ+3)/2
       f%cp(i)%mult = f%c%at(i)%mult
       f%cp(i)%isdeg = .false.
       f%cp(i)%isnnm = .false.
       f%cp(i)%isnuc = .true.
       f%cp(i)%idx = i
       f%cp(i)%ir = 1
       f%cp(i)%ic = 1
       f%cp(i)%lvec = 0
       f%cp(i)%name = f%c%at(i)%name
       f%cp(i)%rbeta = rbetadef

       ! properties at the nuclei
       f%cp(i)%brdist = 0d0
       f%cp(i)%brang = 0d0
       call f%grd(f%c%at(i)%r,2,res0_noalloc=f%cp(i)%s)

       ! calculate the point group symbol
       f%cp(i)%pg = f%c%sitesymm(f%cp(i)%x,atomeps)
    enddo

    ! add positions to the complete cp list
    do j = 1, f%c%ncel
       f%cpcel(j) = f%cp(f%c%atcel(j)%idx)
       f%cpcel(j)%idx = f%c%atcel(j)%idx
       f%cpcel(j)%ir = f%c%atcel(j)%ir
       f%cpcel(j)%ic = f%c%atcel(j)%ic
       f%cpcel(j)%lvec = f%c%atcel(j)%lvec

       f%cpcel(j)%x = matmul(f%c%rotm(1:3,1:3,f%cpcel(j)%ir),f%cp(f%cpcel(j)%idx)%x) + &
          f%c%rotm(:,4,f%cpcel(j)%ir) + f%c%cen(:,f%cpcel(j)%ic) + f%cpcel(j)%lvec
       f%cpcel(j)%r = f%c%x2c(f%cpcel(j)%x)
    end do

  end subroutine init_cplist

  !> Given the point xp in crystallographic coordinates, calculates
  !> the nearest CP of type 'type' or non-equivalent index 'idx'. In the
  !> output, nid represents the id (complete CP list), dist is the
  !> distance. If nozero is true, skip zero-distance CPs.
  subroutine nearest_cp(f,xp,nid,dist,type,idx,nozero)
    class(field), intent(in) :: f
    real*8, intent(in) :: xp(:)
    integer, intent(out) :: nid
    real*8, intent(out) :: dist
    integer, intent(in), optional :: type
    integer, intent(in), optional :: idx
    logical, intent(in), optional :: nozero

    real*8, parameter :: eps2 = 1d-10 * 1d-10

    real*8 :: temp(3), d2, d2min
    integer :: j

    ! check if it is a known cp
    nid = 0
    d2min = 1d30
    do j = 1, f%ncpcel
       if (present(type)) then
          if (f%cpcel(j)%typ /= type) cycle
       end if
       if (present(idx)) then
          if (f%cpcel(j)%idx /= idx) cycle
       end if
       temp = f%cpcel(j)%x - xp
       call f%c%shortest(temp,d2)
       if (present(nozero)) then
          if (d2 < eps2) cycle
       end if
       if (d2 < d2min) then
          nid = j
          d2min = d2
       end if
    end do
    dist = sqrt(d2min)

  end subroutine nearest_cp

  !> Identify a CP in the unit cell. Input: position in cryst
  !> coords. Output: the ncpcel CP index, or 0 if none found. eps is
  !> the distance threshold.
  function identify_cp(f,x0,eps)
    class(field), intent(in) :: f
    integer :: identify_cp
    real*8, intent(in) :: x0(3)
    real*8, intent(in) :: eps

    real*8 :: x(3), dist2, eps2
    integer :: i

    identify_cp = 0
    eps2 = eps*eps
    do i = 1, f%ncpcel
       x = x0 - f%cpcel(i)%x
       call f%c%shortest(x,dist2)
       if (dist2 < eps2) then
          identify_cp = i
          return
       end if
    end do

  end function identify_cp

  !> Test the muffin tin discontinuity. ilvl = 0: quiet. ilvl = 1:
  !> normal output.  ilvl = 2: verbose output.
  subroutine testrmt(f,ilvl,errmsg)
    use tools_io, only: uout, ferror, warning, string, fopen_write, fclose
    use types, only: scalar_value
    use param, only: pi
    class(field), intent(inout) :: f
    integer, intent(in) :: ilvl
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: n, i, j
    integer :: ntheta, nphi
    integer :: nt, np
    real*8 :: phi, theta, dir(3), xnuc(3), xp(3)
    real*8 :: fin, fout, gfin, gfout
    real*8 :: r, rmt
    character*4 :: label
    character(len=:), allocatable :: linefile
    integer :: luline, luplane
    integer  :: npass(f%c%nneq), nfail(f%c%nneq)
    logical :: ok
    real*8 :: epsm, epsp, mepsm, mepsp, dif, dosum, mindif, maxdif
    type(scalar_value) :: res

    real*8, parameter :: eps = 1d-3

    errmsg = ""
    if (f%type /= type_wien .and. f%type /= type_elk) then
       errmsg = "field must be of wien or elk type"
       return
    end if

    write (uout,'("* Muffin-tin discontinuity test")')

    ntheta = 10
    nphi = 10
    do n = 1, f%c%nneq
       if (f%type == type_wien) then
          rmt = f%wien%rmt_atom(f%c%at(n)%x)
       else
          rmt = f%elk%rmt_atom(f%c%at(n)%x)
       end if
       mepsm = 0d0
       mepsp = 0d0
       if (ilvl > 1) then
          write (uout,'("+ Analysis of the muffin tin discontinuity for atom ",A)') string(n)
          write (uout,'("  ntheta = ",A)') string(ntheta)
          write (uout,'("  nphi = ",A)') string(nphi)
       end if

       xnuc = f%c%at(n)%x
       if (ilvl > 1) write (uout,'("  coords = ",3(A,X))') (string(xnuc(j),'f',decimal=9),j=1,3)
       xnuc = f%c%x2c(xnuc)

       if (ilvl > 1) then
          write (uout,'("  rmt = ",A)') string(rmt,'f',decimal=7)
          write (uout,'(2(A8,X),6(A12,X),A4)') "Azim.", "Polar", "f_in",&
             "f_out", "f_in-f_out", "gf_in", "gf_out", "gf_in-gf_out", "ok?"
          write (uout,'(100("-"))')
       end if
       npass(n) = 0
       nfail(n) = 0
       dosum = 0d0
       mindif = 1d10
       maxdif = -1d10
       if (ilvl > 1) then
          ! write line
          linefile = "plane_" // string(n,2,pad0=.true.) // ".dbg"
          luplane = fopen_write(linefile)
          write (luplane,'("#",A,I3)') " atom: ", n
          write (luplane,'("#",A,1p,3(E20.13,X))') " at: ", f%c%at(n)%x
          write (luplane,'("#",A,1p,3(E20.13,X))') " atc: ", xnuc
          write (luplane,'("#",A,1p,E20.13)') " rmt: ", rmt
          write (luplane,'("#  theta phi in out")')
       end if
       do nt = 1, ntheta
          do np = 0, nphi
             if ((np == 0 .or. np == nphi) .and. nt /= 1) cycle
             phi = real(np,8) * pi / nphi
             theta = real(nt,8) * 2d0 * pi / ntheta
             dir(1) = 1d0 * cos(theta) * sin(phi)
             dir(2) = 1d0 * sin(theta) * sin(phi)
             dir(3) = 1d0 * cos(phi)

             xp = xnuc + (rmt+eps) * dir
             call f%grd(xp,1,res0=res)
             fout = res%f
             gfout = dot_product(res%gf,xp-xnuc) / (rmt+eps)
             xp = xnuc + (rmt-eps) * dir
             call f%grd(xp,1,res0=res)
             fin = res%f
             gfin = dot_product(res%gf,xp-xnuc) / (rmt-eps)

             dif = fout - fin
             dosum = dosum + dif * dif
             if (dif < mindif) mindif = dif
             if (dif > maxdif) maxdif = dif

             if (ilvl > 1) then
                ! write line
                write (luplane,'(1p,4(E20.13,X))') theta, phi, fin, fout
             end if

             if (gfin*gfout > 0d0) then
                label = "pass"
                npass(n) = npass(n) + 1
             else
                label = "fail"
                if (ilvl > 2) then
                   ! write line
                   linefile = "line_" // string(n,2,pad0=.true.) // "_" // string(nt,3,pad0=.true.) //&
                      "_" // string(np,3,pad0=.true.) // ".dbg"
                   luline = fopen_write(linefile)
                   write (luline,'("#",A,I3)') " atom: ", n
                   write (luline,'("#",A,1p,3(E20.13,X))') " at: ", f%c%at(n)%x
                   write (luline,'("#",A,1p,3(E20.13,X))') " atc: ", xnuc
                   write (luline,'("#",A,1p,E20.13)') " rmt: ", rmt
                   write (luline,'("#",A,1p,3(E20.13,X))') " dir: ", dir
                   write (luline,'("#",A,1p,E20.13)') " r_ini: ", 0.50d0 * rmt
                   write (luline,'("#",A,1p,E20.13)') " r_end: ", 4.50d0 * rmt
                   do i = 0, 1000
                      r = 0.50d0 * rmt + (real(i,8) / 1000) * 4d0 * rmt
                      xp = xnuc + r * dir
                      call f%grd(xp,1,res0=res)
                      write (luline,'(1p,3(E20.13,X))') r, res%f, dot_product(res%gf,xp-xnuc) / r
                   end do
                   call fclose(luline)
                end if
                epsm = 0d0
                epsp = 0d0
                mepsm = min(epsm,mepsm)
                mepsp = max(epsp,mepsp)
                nfail(n) = nfail(n) + 1
             end if
             if (ilvl > 1) write (uout,'(2(F8.4,X),1p,6(E12.4,X),0p,A4)') &
                theta, phi, fin, fout, fin-fout, gfin, gfout, gfin-gfout, label
          end do
       end do
       dosum = sqrt(dosum / (npass(n)+nfail(n)))
       if (ilvl > 1) then
          write (uout,'(100("-"))')
          write (uout,*)
       end if
       if (ilvl > 1) then
          call fclose(luplane)
       end if
       if (nfail(n) > 0) then
          write (uout,'("  Atom: ",A," delta_m = ",A," delta_p = ",A)') &
             string(n), string(mepsm+1d-3,'f',decimal=6), string(mepsp+1d-3,'f',decimal=6)
          write (uout,*)
       end if
       write (uout,'("  Atom: ",A," rmt= ",A," RMS/max/min(fout-fin) = ",3(A,2X))') &
          string(n), string(rmt,'f',decimal=7), string(dosum,'f',decimal=6), &
          string(maxdif,'f',decimal=6), string(mindif,'f',decimal=6)
    end do

    ok = .true.
    if (ilvl > 0) then
       write (uout,'("+ Summary ")')
       write (uout,'(A4,3(X,A7))') "Atom", "Pass", "Fail", "Total"
    end if
    do n = 1, f%c%nneq
       if (ilvl > 0) write (uout,'(I4,3(X,I7))') n, npass(n), nfail(n), npass(n)+nfail(n)
       ok = ok .and. (nfail(n) == 0)
    end do
    if (ilvl > 0) write (uout,*)
    write (uout,'("+ Assert - no spurious CPs on the muffin tin surface: ",L1/)') ok
    if (.not.ok) call ferror('testrmt','Spurious CPs on the muffin tin surface!',warning)

  end subroutine testrmt

  !> Test the speed of the grd call by calculating npts random point
  !> in the unit cell. Write the results to the standard output.
  subroutine benchmark(f,npts)
    use tools_io, only: uout, string
    use types, only: scalar_value
    implicit none
    class(field), intent(inout) :: f
    integer, intent(in) :: npts

    integer :: wpts(f%c%nneq+1)
    integer :: i, j
    real*8 :: x(3), aux(3), dist
    integer :: c1, c2, rate
    real*8, allocatable :: randn(:,:,:)
    type(scalar_value) :: res
    logical :: inrmt

    write (uout,'("* Benchmark of the field ")')
    write (uout,'("* Field : ",A)') string(f%id)

    if (f%type == type_wien .or. f%type == type_elk) then
       wpts = 0
       allocate(randn(3,npts,f%c%nneq+1))

       out: do while (any(wpts(1:f%c%nneq+1) < npts))
          call random_number(x)
          do i = 1, f%c%ncel
             if (f%c%atcel(i)%idx > f%c%nneq) cycle
             aux = x - f%c%atcel(i)%x
             aux = f%c%x2c(aux - nint(aux))
             dist = dot_product(aux,aux)
             if (f%type == type_wien) then
                inrmt = (dist < f%wien%rmt_atom(f%c%at(f%c%atcel(i)%idx)%x)**2)
             else
                inrmt = (dist < f%elk%rmt_atom(f%c%at(f%c%atcel(i)%idx)%x)**2)
             end if
             if (inrmt) then
                if (wpts(f%c%atcel(i)%idx) >= npts) cycle out
                wpts(f%c%atcel(i)%idx) = wpts(f%c%atcel(i)%idx) + 1
                randn(:,wpts(f%c%atcel(i)%idx),f%c%atcel(i)%idx) = f%c%x2c(x)
                cycle out
             end if
          end do
          if (wpts(f%c%nneq+1) >= npts) cycle out
          wpts(f%c%nneq+1) = wpts(f%c%nneq+1) + 1
          randn(:,wpts(f%c%nneq+1),f%c%nneq+1) = f%c%x2c(x)
       end do out

       write (uout,'("* Benchmark of muffin / interstitial grd ")')
       write (uout,'("* Number of points per zone : ",A)') string(npts)
       do i = 1, f%c%nneq+1
          call system_clock(count=c1,count_rate=rate)
          do j = 1, npts
             call f%grd(randn(:,j,i),0,res0=res)
          end do
          call system_clock(count=c2)
          if (i <= f%c%nneq) then
             write (uout,'("* Atom : ",A)') string(i)
          else
             write (uout,'("* Interstitial ")')
          end if
          write (uout,'("* Total wall time : ",A)') trim(string(real(c2-c1,8) / rate,'f',12,6)) // " s"
          write (uout,'("* Avg. wall time per call : ",A)') &
             trim(string(real(c2-c1,8) / rate / real(npts,8) * 1d6,'f',12,4)) // " us"
       end do
       write (uout,*)
       deallocate(randn)

    else
       allocate(randn(3,npts,1))

       call random_number(randn)
       do i = 1, npts
          randn(1:3,i,1) = f%c%x2c(randn(1:3,i,1))
       end do

       ! grd
       write (uout,'("  Benchmark of the grd call ")')
       write (uout,'("  Number of points : ",A)') string(npts)
       call system_clock(count=c1,count_rate=rate)
       do i = 1, npts
          call f%grd(randn(:,i,1),0,res0=res)
       end do
       call system_clock(count=c2)
       write (uout,'("  Total wall time : ",A)') trim(string(real(c2-c1,8) / rate,'f',12,6)) // " s"
       write (uout,'("  Avg. wall time per call : ",A)') &
          trim(string(real(c2-c1,8) / rate / real(npts,8) * 1d6,'f',12,4)) // " us"
       write (uout,*)

       deallocate(randn)

    end if

  end subroutine benchmark

  !> Do a Newton-Raphson search at point r (Cartesian). A CP is found
  !> when the gradient is less than gfnormeps. ier is the exit code: 0
  !> (success), 1 (singular Hessian), and 2 (too many iterations).
  subroutine newton(f,r,gfnormeps,ier)
    use tools_math, only: detsym
    use types, only: scalar_value_noalloc
    class(field), intent(inout) :: f
    real*8, dimension(3), intent(inout) :: r
    integer, intent(out) :: ier
    real*8, intent(in) :: gfnormeps

    real*8 :: r1(3), xx(3), er
    integer :: iw(3)
    integer :: it
    type(scalar_value_noalloc) :: res

    integer, parameter :: maxit = 200

    do it = 1, maxit
       ! Evaluate and stop criterion
       call f%grd(r,2,res0_noalloc=res)
       if (res%gfmod < gfnormeps) then
          ier = 0
          return
       end if

       ! Invert h matrix and do a Newton-Raphson step (H^{-1}*grad).
       if (abs(detsym(res%hf)) < 1d-30) then
          ier = 1
          return
       end if
       call dgeco(res%hf,3,3,iw,er,r1)
       call dgedi(res%hf,3,3,iw,xx,r1,1)
       r = r - matmul(res%hf,res%gf)
    end do

    ! Too many iterations
    ier = 2

  end subroutine newton

  !> Generalized gradient tracing routine. The gp integration starts
  !> at xpoint (Cartesian) with step step (step < 0 for a slow, i.e.,
  !> 1d-3, start). iup = 1 if the gp is traced up the density, -1 if
  !> down. mstep = max. number of steps. nstep = actual number of
  !> steps (output). ier = 0 (correct), 1 (short step), 2 (too many
  !> iterations), 3 (outside molcell in molecules). extinf = .true.
  !> fills the ax (position, cryst), arho (density), agrad (gradient),
  !> ah (hessian) arrays describing the path. up2r (optional), trace
  !> the gp only up to a certain distance reffered to xref
  !> (cartesian). up2rho, up to a density. up2beta = .true.  , stop
  !> when reaching a beta-sphere. upflag = true (output) if ended
  !> through one of up2r or up2rho.
  subroutine gradient (fid, xpoint, iup, nstep, mstep, ier, extinf, &
    ax, arho, agrad, ah, up2r, xref, up2rho, up2beta, upflag)
    use global, only: nav_step, nav_gradeps, rbetadef
    use tools_io, only: ferror, faterr
    use types, only: scalar_value
    use tools_math, only: eigns
    class(field), intent(inout) :: fid
    real*8, dimension(3), intent(inout) :: xpoint
    integer, intent(in) :: iup
    integer, intent(out) :: nstep
    integer, intent(in) :: mstep
    integer, intent(out) :: ier
    integer, intent(in) :: extinf
    real*8, intent(out), dimension(3,mstep), optional :: ax
    real*8, intent(out), dimension(mstep), optional :: arho
    real*8, intent(out), dimension(3,mstep), optional :: agrad
    real*8, intent(out), dimension(3,3,mstep), optional :: ah
    real*8, intent(in), optional :: up2r, up2rho
    logical, intent(in), optional :: up2beta
    real*8, intent(in), dimension(3), optional :: xref
    logical, intent(out), optional :: upflag

    real*8, parameter :: minstep = 1d-7
    integer, parameter :: mhist = 5

    integer :: i, j
    real*8 :: t, h0, hini
    real*8 :: dx(3), scalhist(mhist)
    real*8 :: xlast(3), xlast2(3), len, xold(3), xini(3)
    real*8 :: sphrad, xnuc(3), cprad, xcp(3), dist2
    integer :: idnuc, idcp, nhist
    integer :: lvec(3)
    logical :: ok
    type(scalar_value) :: res

    ! initialization
    ier = 0
    t = 0d0
    h0 = abs(NAV_step) * iup
    hini = h0
    xini = fid%c%c2x(xpoint)
    scalhist = 1d0
    nhist = 0
    xlast2 = xpoint
    xlast = xpoint

    if (present(up2r)) then
       if (present(xref)) then
          xlast2 = xref
          xlast = xref
       else
          call ferror ('gradient','up2r but no reference', faterr)
       end if
       len = 0d0
    end if
    if (present(upflag)) then
       upflag = .false.
    end if

    ! initialize spherical coordinates navigation
    xold = 10d0 ! dummy!

    ! properties at point
    call fid%grd(xpoint,2,res0=res)

    do nstep = 1, mstep
       ! tasks in crystallographic
       xpoint = fid%c%c2x(xpoint)

       ! get nearest nucleus
       idnuc = 0
       call fid%c%nearest_atom(xpoint,idnuc,sphrad,lvec)
       xnuc = fid%c%x2c(fid%c%atcel(idnuc)%x - lvec)
       idnuc = fid%c%atcel(idnuc)%idx

       ! get nearest -3 CP (idncp) and +3 CP (idccp), skip hydrogens
       if ((fid%typnuc==-3 .and. iup==1 .or. fid%typnuc==3 .and. iup==-1) .and.&
          fid%c%at(idnuc)%z /= 1) then
          idcp = idnuc
          cprad = sphrad
          xcp = xnuc
       else
          idcp = 0
          cprad = 1d15
          xcp = 0d0
       end if
       if (fid%ncpcel > 0) then
          cprad = cprad * cprad
          do i = 1, fid%ncpcel
             if (.not.(fid%cpcel(i)%typ==-3 .and. iup==1 .or. fid%cpcel(i)%typ==3 .and. iup==-1)) cycle  ! only cages if down, only ncps if up
             dx = xpoint - fid%cpcel(i)%x
             call fid%c%shortest(dx,dist2)
             if (dist2 < cprad) then
                cprad = dist2
                idcp = fid%cpcel(i)%idx
                xcp = fid%c%x2c(fid%cpcel(i)%x + nint(xpoint-fid%cpcel(i)%x-dx))
             end if
          end do
          cprad = sqrt(cprad)
       end if

       ! is it a nuclear position? 
       ok = .false.
       ! beta-sphere if up2beta is activated
       if (present(up2beta)) then
          if (up2beta .and. idcp/=0) then
             ok = ok .or. (cprad <= fid%cp(idcp)%rbeta)
          else
             ok = ok .or. (cprad <= Rbetadef)
          end if
       else
          ok = ok .or. (cprad <= Rbetadef)
       end if
       if (ok) then
          xpoint = xcp
          if (extinf > 0) then
             ax(:,nstep) = fid%c%c2x(xpoint)
             if (extinf > 1) then
                arho(nstep) = res%f
                agrad(:,nstep) =  (/ 0d0, 0d0, 0d0 /)
                forall (i=1:3, j=1:3) ah(i,j,nstep) = 0d0
                forall (i=1:3) ah(i,i,nstep) = 1d0
             end if
          end if
          ier = 0
          return
       end if

       ! save info
       if (extinf > 0) then
          ax(:,nstep) = xpoint
          if (extinf > 1) then
             arho(nstep) = res%f
             agrad(:,nstep) = res%gf
             ah(:,:,nstep) = res%hf
          end if
       end if

       ! is it outside the molcell?
       if (fid%c%ismolecule .and. iup==-1) then
          if (xpoint(1) < fid%c%molborder(1) .or. xpoint(1) > (1d0-fid%c%molborder(1)) .or.&
             xpoint(2) < fid%c%molborder(2) .or. xpoint(2) > (1d0-fid%c%molborder(2)) .or.&
             xpoint(3) < fid%c%molborder(3) .or. xpoint(3) > (1d0-fid%c%molborder(3))) then
             ier = 3
             return
          end if
       endif

       ! tasks in cartesian
       xpoint = fid%c%x2c(xpoint)

       ! is it a cp?
       ok = (res%gfmod < NAV_gradeps)
       if (ok) then
          ier = 0
          return
       end if

       ! up 2 rho?
       if (present(up2rho)) then
          if (iup == 1 .and. res%f > up2rho .or. iup == -1 .and. res%f < up2rho) then
             if (present(upflag)) then
                upflag = .true.
             end if
             ier = 0
             return
          end if
       end if

       ! up 2 r?
       if (present(up2r)) then
          len = len + sqrt(dot_product(xpoint-xlast,xpoint-xlast))
          if (len > up2r) then
             if (present(upflag)) then
                upflag = .true.
             end if
             ier = 0
             return
          end if
       end if

       ! take step
       xlast2 = xlast
       xlast = xpoint
       ok = adaptive_stepper(fid,xpoint,h0,hini,NAV_gradeps,res)

       ! add to the trajectory angle history, terminate the gradient if the 
       ! trajectory bounces around mhist times
       nhist = mod(nhist,mhist) + 1
       scalhist(nhist) = dot_product(xlast-xlast2,xpoint-xlast)
       ok = ok .and. .not.(all(scalhist < 0d0))

       if (.not.ok .or. abs(h0) < minstep) then
          ier = 1
          return
       end if
    end do

    nstep = mstep
    ier = 2

  end subroutine gradient

  !> Integration using adaptive_stepper step, old scheme. Grow the step if
  !> the angle of two successive steps is almost 180, shrink if it is
  !> less than 90 degrees.
  function adaptive_stepper(fid,xpoint,h0,maxstep,eps,res)
    use global, only: nav_stepper, nav_stepper_heun, nav_stepper_rkck, nav_stepper_dp,&
       nav_stepper_bs, nav_stepper_euler, nav_maxerr
    use tools_math, only: norm
    use types, only: scalar_value
    use param, only: vsmall
    logical :: adaptive_stepper
    type(field), intent(inout) :: fid
    real*8, intent(inout) :: xpoint(3)
    real*8, intent(inout) :: h0
    real*8, intent(in) :: maxstep, eps
    type(scalar_value), intent(inout) :: res

    integer :: ier, iup
    real*8 :: grdt(3), ogrdt(3)
    real*8 :: xtemp(3), escalar, xerrv(3)
    real*8 :: nerr
    logical :: ok, first

    real*8, parameter :: h0break = 1.d-10

    adaptive_stepper = .true.
    ier = 1
    if (h0 > 0) then
       iup = 1
    else
       iup = -1
    end if

    grdt = res%gf / (res%gfmod + VSMALL)
    ogrdt = grdt

    first = .true.
    do while (ier /= 0)
       ! new point
       if (NAV_stepper == NAV_stepper_euler) then
          call stepper_euler1(xpoint,grdt,h0,xtemp)
       else if (NAV_stepper == NAV_stepper_heun) then
          call stepper_heun(fid,xpoint,grdt,h0,xtemp,xerrv,res)
       else if (NAV_stepper == NAV_stepper_rkck) then
          call stepper_rkck(fid,xpoint,grdt,h0,xtemp,xerrv,res)
       else if (NAV_stepper == NAV_stepper_dp) then
          call stepper_dp(fid,xpoint,grdt,h0,xtemp,xerrv,res)
       else if (NAV_stepper == NAV_stepper_bs) then
          call stepper_bs(fid,xpoint,grdt,h0,xtemp,xerrv,res)
       end if

       ! FSAL for BS stepper
       if (NAV_stepper /= NAV_stepper_bs) then
          call fid%grd(xtemp,2,res0=res)
       end if

       ! poor man's adaptive step size in Euler
       if (NAV_stepper == NAV_stepper_euler .or. NAV_stepper == NAV_stepper_heun) then
          ! angle with next step
          escalar = dot_product(ogrdt,res%gf / (res%gfmod+VSMALL))

          ! gradient eps in cartesian
          ok = (res%gfmod < 0.99d0*eps)

          ! Check if they differ in > 90 deg.
          if (escalar < 0.d0.and..not.ok) then
             if (abs(h0) >= h0break) then
                h0 = 0.5d0 * h0
                ier = 1
             else
                adaptive_stepper = .false.
                return
             end if
          else
             ! Accept point. If angle is favorable, take longer steps
             if (escalar > 0.9 .and. first) &
                h0 = dsign(min(abs(maxstep), abs(1.6d0*h0)),maxstep)
             ier = 0
             xpoint = xtemp
          end if
       else
          ! use the error estimate
          nerr = norm(xerrv)
          if (nerr < NAV_maxerr) then
             ! accept point
             ier = 0
             xpoint = xtemp
             ! if this is the first time through, and the norm is very small, propose a longer step
             if (first .and. nerr < NAV_maxerr/10d0) &
                h0 = dsign(min(abs(maxstep), abs(1.6d0*h0)),maxstep)
          else
             ! propose a new shorter step using the error estimate
             h0 = 0.9d0 * h0 * NAV_maxerr / nerr
             if (abs(h0) < VSMALL) then
                adaptive_stepper = .false.
                return
             end if
          endif
       end if
       first = .false.
    enddo

  end function adaptive_stepper

  !> Euler stepper.
  subroutine stepper_euler1(xpoint,grdt,h0,xout)
    
    real*8, intent(in) :: xpoint(3), h0, grdt(3)
    real*8, intent(out) :: xout(3)
  
    xout = xpoint + h0 * grdt
  
  end subroutine stepper_euler1

  !> Heun stepper.
  subroutine stepper_heun(fid,xpoint,grdt,h0,xout,xerr,res)
    use types, only: scalar_value
    use param, only: vsmall
    
    type(field), intent(inout) :: fid
    real*8, intent(in) :: xpoint(3), h0, grdt(3)
    real*8, intent(out) :: xout(3), xerr(3)
    type(scalar_value), intent(inout) :: res
    
    real*8 :: ak2(3)

    xerr = xpoint + h0 * grdt
    call fid%grd(xerr,2,res0=res)
    ak2 = res%gf / (res%gfmod+VSMALL)
    xout = xpoint + 0.5d0 * h0 * (ak2 + grdt)
    xerr = xout - xerr
  
  end subroutine stepper_heun

  !> Bogacki-Shampine embedded 2(3) method, fsal
  subroutine stepper_bs(fid,xpoint,grdt,h0,xout,xerr,res)
    use types, only: scalar_value
    use param, only: vsmall
    
    type(field), intent(inout) :: fid
    real*8, intent(in) :: xpoint(3), h0, grdt(3)
    real*8, intent(out) :: xout(3), xerr(3)
    type(scalar_value), intent(inout) :: res

    real*8, dimension(3) :: ak1, ak2, ak3, ak4

    ak1 = grdt

    xout = xpoint + h0 * (0.5d0*ak1)
    call fid%grd(xout,2,res0=res)
    ak2 = res%gf / (res%gfmod+VSMALL)

    xout = xpoint + h0 * (0.75d0*ak2)
    call fid%grd(xout,2,res0=res)
    ak3 = res%gf / (res%gfmod+VSMALL)

    xout = xpoint + h0 * (0.75d0*ak2)
    call fid%grd(xout,2,res0=res)
    ak3 = res%gf / (res%gfmod+VSMALL)

    xout = xpoint + h0 * (2d0/9d0*ak1 + 1d0/3d0*ak2 + 4d0/9d0*ak3)
    call fid%grd(xout,2,res0=res)
    ak4 = res%gf / (res%gfmod+VSMALL)

    xerr = xpoint + h0 * (7d0/24d0*ak1 + 1d0/4d0*ak2 + 1d0/3d0*ak3 + 1d0/8d0*ak4) - xout

  end subroutine stepper_bs

  !> Runge-Kutta-Cash-Karp embedded 4(5)-order, local extrapolation.
  subroutine stepper_rkck(fid,xpoint,grdt,h0,xout,xerr,res)
    use types, only: scalar_value
    use param, only: vsmall
    
    type(field), intent(inout) :: fid
    real*8, intent(in) :: xpoint(3), grdt(3), h0
    real*8, intent(out) :: xout(3), xerr(3)
    type(scalar_value), intent(inout) :: res

    real*8, parameter :: B21=.2d0, &
         B31=3.d0/40.d0, B32=9.d0/40.d0,&
         B41=.3d0, B42=-.9d0, B43=1.2d0,&
         B51=-11.d0/54.d0, B52=2.5d0, B53=-70.d0/27.d0, B54=35.d0/27.d0,&
         B61=1631.d0/55296.d0,B62=175.d0/512.d0, B63=575.d0/13824.d0, B64=44275.d0/110592.d0, B65=253.d0/4096.d0,&
         C1=37.d0/378.d0, C3=250.d0/621.d0, C4=125.d0/594.d0, C6=512.d0/1771.d0,&
         DC1=C1-2825.d0/27648.d0, DC3=C3-18575.d0/48384.d0, DC4=C4-13525.d0/55296.d0, DC5=-277.d0/14336.d0, DC6=C6-.25d0
    real*8, dimension(3) :: ak2, ak3, ak4, ak5, ak6
    
    xout = xpoint + h0*B21*grdt

    call fid%grd(xout,2,res0=res)
    ak2 = res%gf / (res%gfmod+VSMALL)
    xout = xpoint + h0*(B31*grdt+B32*ak2)

    call fid%grd(xout,2,res0=res)
    ak3 = res%gf / (res%gfmod+VSMALL)
    xout = xpoint + h0*(B41*grdt+B42*ak2+B43*ak3)

    call fid%grd(xout,2,res0=res)
    ak4 = res%gf / (res%gfmod+VSMALL)
    xout = xpoint + h0*(B51*grdt+B52*ak2+B53*ak3+B54*ak4)

    call fid%grd(xout,2,res0=res)
    ak5 = res%gf / (res%gfmod+VSMALL)
    xout = xpoint + h0*(B61*grdt+B62*ak2+B63*ak3+B64*ak4+B65*ak5)

    call fid%grd(xout,2,res0=res)
    ak6 = res%gf / (res%gfmod+VSMALL)
    xout = xpoint + h0*(C1*grdt+C3*ak3+C4*ak4+C6*ak6)
    xerr = h0*(DC1*grdt+DC3*ak3+DC4*ak4+DC5*ak5+DC6*ak6)

  end subroutine stepper_rkck

  !> Doermand-Prince embedded 4(5)-order, local extrapolation.
  subroutine stepper_dp(fid,xpoint,grdt,h0,xout,xerr,res)
    use types, only: scalar_value
    use param, only: vsmall
    
    type(field), intent(inout) :: fid
    real*8, intent(in) :: xpoint(3), grdt(3), h0
    real*8, intent(out) :: xout(3), xerr(3)
    type(scalar_value), intent(inout) :: res

    real*8, parameter :: dp_a(7,7) = reshape((/&
       0.0d0,  0d0,0d0,0d0,0d0,0d0,0d0,&
       1d0/5d0,         0.0d0,0d0,0d0,0d0,0d0,0d0,&
       3d0/40d0,        9d0/40d0,       0.0d0,0d0,0d0,0d0,0d0,&
       44d0/45d0,      -56d0/15d0,      32d0/9d0,        0d0,0d0,0d0,0d0,&
       19372d0/6561d0, -25360d0/2187d0, 64448d0/6561d0, -212d0/729d0,  0d0,0d0,0d0,&
       9017d0/3168d0,  -355d0/33d0,     46732d0/5247d0,  49d0/176d0,  -5103d0/18656d0, 0d0,0d0,&
       35d0/384d0,      0d0,            500d0/1113d0,    125d0/192d0, -2187d0/6784d0,  11d0/84d0,      0d0&
       /),shape(dp_a))
    real*8, parameter :: dp_b2(7) = (/5179d0/57600d0, 0d0, 7571d0/16695d0, 393d0/640d0,&
       -92097d0/339200d0, 187d0/2100d0, 1d0/40d0/)
    real*8, parameter :: dp_b(7) = (/ 35d0/384d0, 0d0, 500d0/1113d0, 125d0/192d0, &
       -2187d0/6784d0, 11d0/84d0, 0d0 /)
    real*8, parameter :: dp_c(7) = dp_b2 - dp_b
    real*8, dimension(3) :: ak2, ak3, ak4, ak5, ak6, ak7

    xout = xpoint + h0*dp_a(2,1)*grdt

    call fid%grd(xout,2,res0=res)
    ak2 = res%gf / (res%gfmod+VSMALL)
    xout = xpoint + h0*(dp_a(3,1)*grdt+dp_a(3,2)*ak2)

    call fid%grd(xout,2,res0=res)
    ak3 = res%gf / (res%gfmod+VSMALL)
    xout = xpoint + h0*(dp_a(4,1)*grdt+dp_a(4,2)*ak2+dp_a(4,3)*ak3)

    call fid%grd(xout,2,res0=res)
    ak4 = res%gf / (res%gfmod+VSMALL)
    xout = xpoint + h0*(dp_a(5,1)*grdt+dp_a(5,2)*ak2+dp_a(5,3)*ak3+dp_a(5,4)*ak4)

    call fid%grd(xout,2,res0=res)
    ak5 = res%gf / (res%gfmod+VSMALL)
    xout = xpoint + h0*(dp_a(6,1)*grdt+dp_a(6,2)*ak2+dp_a(6,3)*ak3+dp_a(6,4)*ak4+dp_a(6,5)*ak5)

    call fid%grd(xout,2,res0=res)
    ak6 = res%gf / (res%gfmod+VSMALL)
    xout = xpoint + h0*(dp_b(1)*grdt+dp_b(2)*ak2+dp_b(3)*ak3+dp_b(4)*ak4+dp_b(5)*ak5+dp_b(6)*ak6)

    call fid%grd(xout,2,res0=res)
    ak7 = res%gf / (res%gfmod+VSMALL)
    xerr = h0*(dp_c(1)*grdt+dp_c(2)*ak2+dp_c(3)*ak3+dp_c(4)*ak4+dp_c(5)*ak5+dp_c(6)*ak6+dp_c(7)*ak7)
    xout = xout + xerr

  end subroutine stepper_dp

  !> Prune a gradient path. A gradient path is given by the n points
  !> in x (fractional coordinates) referred to crystal structure c.
  !> In output, the number of points in the path is reduced so that
  !> the distances between adjacent points are at least fprune. The
  !> reduced number of points is returned in n, and the fractional
  !> coordinates in x(:,1:n).
  subroutine prunepath(c,n,x,fprune)
    use crystalmod, only: crystal
    type(crystal), intent(in) :: c
    integer, intent(inout) :: n
    real*8, intent(inout) :: x(3,n)
    real*8, intent(in) :: fprune

    integer :: i, nn
    real*8 :: x0(3)

    ! prune the path
    x0 = x(:,1)
    nn = 1
    do i = 1, n
       if (.not.c%are_close(x(:,i),x0,fprune)) then
          nn = nn + 1
          x(:,nn) = x(:,i)
          x0 = x(:,i)
       end if
    end do
    n = nn

  end subroutine prunepath

end module fieldmod