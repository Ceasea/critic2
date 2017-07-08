! Copyright (c) 2015 Alberto Otero de la Roza
! <aoterodelaroza@gmail.com>,
! Ángel Martín Pendás <angel@fluor.quimica.uniovi.es> and Víctor Luaña
! <victor@fluor.quimica.uniovi.es>.
!
! critic2 is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at
! your option) any later version.
!
! critic2 is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see
! <http://www.gnu.org/licenses/>.

! Fragment class.
module fragmentmod
  use types, only: anyatom
  implicit none

  private
  public :: fragment
  public :: realloc_fragment
  
  !> Type for a fragment of the crystal
  type fragment
     integer :: nat !< Number of atoms in the fragment
     type(anyatom), allocatable :: at(:) !< Atoms in the fragment
   contains
     procedure :: init => fragment_init
     procedure :: append
     procedure :: merge_array
     procedure :: cmass
  end type fragment

contains

  !> Initialize a fragment
  subroutine fragment_init(fr)
    class(fragment), intent(inout) :: fr
    
    if (allocated(fr%at)) deallocate(fr%at)
    allocate(fr%at(1))
    fr%nat = 0
    
  end subroutine fragment_init

  !> Merge two or more fragments, delete repeated atoms. If fr already
  !> has a fragment, then add to it if add = .true. (default:
  !> .true.).
  subroutine merge_array(fr,fra,add) 
    use types, only: realloc
    class(fragment), intent(inout) :: fr
    type(fragment), intent(in) :: fra(:)
    logical, intent(in), optional :: add
    
    real*8, parameter :: eps = 1d-10

    integer :: i, j, k, nat0, nat1
    real*8 :: x(3)
    logical :: found, add0
    
    add0 = .true.
    if (present(add)) add0 = add

    nat0 = 0
    do i = 1, size(fra)
       nat0 = nat0 + fra(i)%nat
    end do
    if (.not.add) then
       if (allocated(fr%at)) deallocate(fr%at)
       allocate(fr%at(nat0))
       fr%nat = 0
    end if

    do i = 1, size(fra)
       nat0 = fr%nat
       nat1 = fr%nat + fra(i)%nat
       if (nat1 > size(fr%at)) call realloc(fr%at,2*nat1)
       do j = 1, fra(i)%nat
          found = .false.
          do k = 1, nat0
             x = abs(fra(i)%at(j)%r - fr%at(k)%r)
             found = all(x < eps)
             if (found) exit
          end do
          if (.not.found) then
             nat0 = nat0 + 1
             fr%at(nat0) = fra(i)%at(j)
          end if
       end do
       fr%nat = nat0
    end do
    call realloc(fr%at,fr%nat)
    
  end subroutine merge_array

  !> Append a fragment to the current fragment, delete repeated atoms.  
  subroutine append(fr,fra) 
    use types, only: realloc
    class(fragment), intent(inout) :: fr
    class(fragment), intent(in) :: fra
    
    real*8, parameter :: eps = 1d-10

    integer :: i, j, k, nat0, nat1
    real*8 :: x(3)
    logical :: found
    
    if (.not.allocated(fr%at)) then
       allocate(fr%at(fra%nat))
    else
       call realloc(fr%at,fr%nat+fra%nat)
    end if

    nat0 = fr%nat
    nat1 = fr%nat + fra%nat
    if (nat1 > size(fr%at)) call realloc(fr%at,2*nat1)
    do j = 1, fra%nat
       found = .false.
       do k = 1, nat0
          x = abs(fra%at(j)%r - fr%at(k)%r)
          found = all(x < eps)
          if (found) exit
       end do
       if (.not.found) then
          nat0 = nat0 + 1
          fr%at(nat0) = fra%at(j)
       end if
    end do
    fr%nat = nat0
    call realloc(fr%at,fr%nat)
    
  end subroutine append

  !> Returns the center of mass (in Cartesian coordinates).  If
  !> weight0 is false, then all atoms have the same weight.
  function cmass(fr,weight0) result (x)
    use param, only: atmass
    class(fragment), intent(in) :: fr
    logical, intent(in), optional :: weight0
    real*8 :: x(3)

    integer :: i
    logical :: weight
    real*8 :: sum

    weight = .true.
    if (present(weight0)) weight = weight0

    x = 0d0
    sum = 0d0
    if (weight) then
       do i = 1, fr%nat
          x = x + atmass(fr%at(i)%z) * fr%at(i)%r
          sum = sum + atmass(fr%at(i)%z)
       end do
    else
       do i = 1, fr%nat
          x = x + fr%at(i)%r
          sum = sum + 1d0
       end do
    end if
    x = x / max(sum,1d-40)

  end function cmass

  !> Adapt the size of an allocatable 1D type(fragment) array
  subroutine realloc_fragment(a,nnew)
    use tools_io, only: ferror, faterr
    type(fragment), intent(inout), allocatable :: a(:)
    integer, intent(in) :: nnew

    type(fragment), allocatable :: temp(:)
    integer :: nold

    if (.not.allocated(a)) &
       call ferror('realloc_fragment','array not allocated',faterr)
    nold = size(a)
    if (nold == nnew) return
    allocate(temp(nnew))

    temp(1:min(nnew,nold)) = a(1:min(nnew,nold))
    call move_alloc(temp,a)

  end subroutine realloc_fragment

end module fragmentmod
